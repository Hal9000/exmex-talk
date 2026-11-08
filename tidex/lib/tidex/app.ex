defmodule Tidex.App do
  @moduledoc """
  Tidex's UI process: render, wait for an event, update, repeat.

  Keyboard input arrives as messages so command output can stream in
  without blocking on a key read. Background command and git processes
  never draw; this process owns the screen.
  """

  @server_probe_interval 250

  alias Tidex.{
    Command,
    Config,
    Failures,
    Git,
    GitInfo,
    GitModal,
    Help,
    Keyboard,
    Open,
    ServerJob,
    ServerProbe,
    Setup,
    State,
    View
  }

  defstruct device: nil,
            state: %State{},
            runner: &Tidex.App.default_runner/3,
            server_runner: &Tidex.App.default_server_runner/3,
            server_stopper: &ServerJob.stop/1,
            server_probe: &ServerProbe.status/1,
            server_waiter: &ServerProbe.wait_closed/1,
            probe_scheduler: &Tidex.App.schedule_probe/2,
            editor_runner: &Open.editor/1,
            browser_runner: &Open.browser/1,
            git_reader: &Git.snapshot/0,
            keys: :device,
            poll_git: false,
            resize: false,
            dimension_reader: &Tidex.App.terminal_dimensions/0,
            notify_ready: nil,
            tty: nil,
            keyboard: nil,
            git_pid: nil,
            resize_handler: nil,
            home: []

  @type t :: %__MODULE__{
          device: Termex.Device.t(),
          state: State.t(),
          runner: (String.t(), pid(), reference() -> {:ok, pid()}),
          server_runner: (String.t(), pid(), reference() -> {:ok, pid()}),
          server_stopper: (pid() | nil -> :ok | {:error, term()}),
          server_probe: (String.t() | nil -> ServerProbe.status()),
          server_waiter: (String.t() | nil -> ServerProbe.status()),
          probe_scheduler: (term(), non_neg_integer() -> term()),
          editor_runner: (String.t() -> term()),
          browser_runner: (String.t() -> term()),
          git_reader: (-> Git.snapshot()),
          keys: :device | :none,
          poll_git: boolean(),
          resize: boolean(),
          dimension_reader: (-> {pos_integer(), pos_integer()}),
          notify_ready: pid() | nil,
          tty: Termex.RawMode.session(),
          keyboard: pid() | nil,
          git_pid: pid() | nil,
          resize_handler: term(),
          home: keyword()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    dimension_reader = Keyword.get(opts, :dimension_reader, &terminal_dimensions/0)
    {width, height} = dimensions(opts, dimension_reader)
    cwd = Path.expand(Keyword.get(opts, :cwd, File.cwd!()))
    injected? = Keyword.has_key?(opts, :config)
    home = Keyword.take(opts, [:home])
    config = Keyword.get(opts, :config) || Config.load(cwd, home)

    setup =
      cond do
        injected? -> nil
        Config.find_file(cwd, home) == nil -> Setup.probe(cwd)
        true -> nil
      end

    config_path =
      Keyword.get(opts, :config_path) ||
        unless(injected?, do: Config.find_file(cwd, home))

    config_root =
      Keyword.get(opts, :config_root) ||
        if(is_binary(config_path), do: Path.dirname(config_path), else: cwd)

    state = %State{
      title: Keyword.get(opts, :title, "Tidex"),
      project_name: Keyword.get(opts, :project_name, config.project),
      test_command: Keyword.get(opts, :test_command, config.test),
      test_format: Keyword.get(opts, :test_format, config.test_format),
      server_command: Keyword.get(opts, :server_command, config.server),
      browser_url: Keyword.get(opts, :browser_url, config.browser),
      editor_command: Keyword.get(opts, :editor_command, config.editor),
      git: Keyword.get(opts, :git, Git.empty()),
      overlay: if(setup, do: :setup, else: nil),
      setup: setup,
      cwd: cwd,
      config_path: config_path,
      config_root: config_root,
      files: Keyword.get(opts, :files, config.files),
      width: width,
      height: height
    }

    runner =
      Keyword.get(opts, :runner) ||
        fn command, notify, ref ->
          Command.start(command, notify, ref: ref, cd: config_root)
        end

    server_runner =
      Keyword.get(opts, :server_runner) ||
        if Keyword.has_key?(opts, :runner) do
          runner
        else
          fn command, notify, ref ->
            ServerJob.start(command, notify, ref: ref, cd: config_root)
          end
        end

    server_stopper =
      Keyword.get(opts, :server_stopper) ||
        if(Keyword.has_key?(opts, :runner), do: &Command.stop/1, else: &ServerJob.stop/1)

    %__MODULE__{
      device: Keyword.get(opts, :device, Termex.Device.stdio()),
      state: state,
      runner: runner,
      server_runner: server_runner,
      server_stopper: server_stopper,
      server_probe: Keyword.get(opts, :server_probe, &ServerProbe.status/1),
      server_waiter: Keyword.get(opts, :server_waiter, &ServerProbe.wait_closed/1),
      probe_scheduler: Keyword.get(opts, :probe_scheduler, &schedule_probe/2),
      editor_runner: Keyword.get(opts, :editor_runner, &Open.editor/1),
      browser_runner: Keyword.get(opts, :browser_runner, &Open.browser/1),
      git_reader: Keyword.get(opts, :git_reader, fn -> Git.snapshot(config_root) end),
      keys: Keyword.get(opts, :keys, :device),
      poll_git: Keyword.get(opts, :poll_git, false),
      resize:
        Keyword.get(
          opts,
          :resize,
          not (Keyword.has_key?(opts, :width) or Keyword.has_key?(opts, :height))
        ),
      dimension_reader: dimension_reader,
      notify_ready: Keyword.get(opts, :notify_ready),
      home: home
    }
  end

  @doc """
  Draw the dashboard and process events until quit.

  Uses Termex raw mode when stdin is a TTY. Tests inject a device and
  can disable the keyboard process with `keys: :none`.
  """
  @spec start(keyword() | t()) :: :ok
  def start(opts_or_app \\ [])

  def start(opts) when is_list(opts) do
    Tidex.UI.run(Keyword.put_new(opts, :name, nil))
  end

  def start(%__MODULE__{} = app) do
    Tidex.UI.run(app)
  end

  @spec step(t(), term()) :: {:cont, t()} | {:quit, t()}
  def step(app, event) do
    app = refresh_dimensions(app)

    case handle_event(app, event) do
      {:cont, app} ->
        app = refresh_dimensions(app)
        View.render(app.device, app.state)
        {:cont, app}

      {:quit, app} ->
        {:quit, app}
    end
  end

  @doc false
  @spec refresh_dimensions(t()) :: t()
  def refresh_dimensions(%{resize: false} = app), do: app

  def refresh_dimensions(app) do
    {width, height} = app.dimension_reader.()
    %{app | state: %{app.state | width: width, height: height}}
  end

  @spec handle_event(t(), term()) :: {:cont, t()} | {:quit, t()}
  def handle_event(app, {:key, key}) when key in ["q", "Q", <<3>>, :eof], do: {:quit, app}

  def handle_event(%{state: %{overlay: :setup}} = app, {:key, key}) when key in ["y", "Y"] do
    {:cont, setup_write(app, :cwd)}
  end

  def handle_event(%{state: %{overlay: :setup}} = app, {:key, key}) when key in ["g", "G"] do
    {:cont, setup_write(app, :git)}
  end

  def handle_event(%{state: %{overlay: :setup}} = app, {:key, key})
      when key in ["n", "N", :esc] do
    {:cont, setup_skip(app)}
  end

  def handle_event(%{state: %{overlay: :setup}} = app, {:key, _key}) do
    {:cont, app}
  end

  def handle_event(%{state: %{modal: %{kind: :fail}}} = app, {:key, :esc}) do
    {:cont, close_fail_modal(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :fail}}} = app, {:key, key})
      when key in ["f", "F"] do
    {:cont, close_fail_modal(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :fail}}} = app, {:key, key})
      when key in ["e", "E"] do
    {:cont, launch_editor(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :fail}}} = app, {:key, :left}) do
    {:cont, cycle_fail_modal(app, -1)}
  end

  def handle_event(%{state: %{modal: %{kind: :fail}}} = app, {:key, :right}) do
    {:cont, cycle_fail_modal(app, 1)}
  end

  def handle_event(%{state: %{modal: %{kind: :fail}}} = app, {:key, _key}) do
    {:cont, app}
  end

  def handle_event(%{state: %{modal: %{kind: :git}}} = app, {:key, key})
      when key in ["g", "G", :esc] do
    {:cont, close_git_modal(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :git}}} = app, {:key, key})
      when key in ["a", "A"] do
    {:cont, git_add(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :git}}} = app, {:key, key})
      when key in ["c", "C"] do
    {:cont, git_commit(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :git}}} = app, {:key, key})
      when key in ["p", "P"] do
    {:cont, git_push(app)}
  end

  def handle_event(
        %{state: %{modal: %{kind: :git} = modal} = state} = app,
        {:key, key}
      )
      when key in [:up, :down, :page_up, :page_down] do
    {:cont, put_state(app, %{modal: GitModal.scroll(modal, key, state)})}
  end

  def handle_event(%{state: %{modal: %{kind: :git}}} = app, {:key, _key}) do
    {:cont, app}
  end

  def handle_event(%{state: %{modal: %{kind: :help}}} = app, {:key, "?"}) do
    {:cont, close_help_modal(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :help, page: :menu}}} = app, {:key, :esc}) do
    {:cont, close_help_modal(app)}
  end

  def handle_event(%{state: %{modal: %{kind: :help, page: {:topic, _}} = modal}} = app, {
        :key,
        :esc
      }) do
    {:cont, put_state(app, %{modal: Help.back(modal)})}
  end

  def handle_event(%{state: %{modal: %{kind: :help, page: :menu} = modal}} = app, {
        :key,
        key
      })
      when key in ["\t", :down, :right] do
    {:cont, put_state(app, %{modal: Help.move(modal, 1)})}
  end

  def handle_event(%{state: %{modal: %{kind: :help, page: :menu} = modal}} = app, {
        :key,
        key
      })
      when key in [:up, :left] do
    {:cont, put_state(app, %{modal: Help.move(modal, -1)})}
  end

  def handle_event(%{state: %{modal: %{kind: :help, page: :menu} = modal}} = app, {
        :key,
        key
      })
      when key in ["\r", "\n"] do
    {:cont, put_state(app, %{modal: Help.open(modal)})}
  end

  def handle_event(
        %{state: %{modal: %{kind: :help, page: {:topic, _}} = modal} = state} = app,
        {:key, key}
      )
      when key in [:up, :down, :page_up, :page_down] do
    {:cont, put_state(app, %{modal: Help.scroll(modal, key, state)})}
  end

  def handle_event(%{state: %{modal: %{kind: :help}}} = app, {:key, _key}) do
    {:cont, app}
  end

  def handle_event(%{state: %{modal: %{kind: :git_info}}} = app, {:key, :esc}) do
    {:cont, put_state(app, %{modal: nil})}
  end

  def handle_event(%{state: %{modal: %{kind: :git_info}}} = app, {:key, _key}) do
    {:cont, app}
  end

  def handle_event(app, {:key, "?"}) do
    {:cont, open_help_modal(app)}
  end

  def handle_event(app, {:key, key}) when key in ["i", "I"] do
    {:cont, put_state(app, %{overlay: nil, modal: GitInfo.modal(app.state.git)})}
  end

  def handle_event(app, {:key, "g"}) do
    {:cont, open_git_modal(app)}
  end

  def handle_event(app, {:key, key}) when key in ["t", "T"] do
    {:cont, start_tests(app)}
  end

  def handle_event(app, {:key, key}) when key in ["s", "S"] do
    {:cont, start_or_restart_server(app)}
  end

  def handle_event(app, {:key, key}) when key in ["x", "X"] do
    {:cont, stop_server(app)}
  end

  def handle_event(%{state: %{browser_url: url}} = app, {:key, key})
      when key in ["b", "B"] and is_binary(url) and url != "" do
    app.browser_runner.(app.state.browser_url)
    {:cont, app}
  end

  def handle_event(app, {:key, key}) when key in ["b", "B"], do: {:cont, app}

  def handle_event(app, {:key, key}) when key in ["f", "F"] do
    {:cont, open_fail_modal(app)}
  end

  def handle_event(app, {:key, "0"}) do
    {:cont, launch_editor(app, file: config_file(app.state))}
  end

  def handle_event(app, {:key, key}) when key in ~w(1 2 3 4) do
    {:cont, open_listed_file(app, String.to_integer(key))}
  end

  def handle_event(app, {:key, _key}), do: {:cont, app}

  def handle_event(app, {:command, ref, :line, line}) do
    {:cont, maybe_append_output(app, ref, line)}
  end

  def handle_event(app, {:command, ref, :exit, status}) do
    {:cont, finish_command(app, ref, status)}
  end

  def handle_event(app, {:server_probe, ref}) do
    {:cont, refresh_server_probe(app, ref)}
  end

  def handle_event(%{state: %{server_ref: ref}} = app, {
        :server_job,
        ref,
        :cleanup_failed,
        _reason
      }) do
    {:cont,
     put_state(app, %{
       server_state: :stop_failed,
       server_ref: nil,
       server_pid: nil
     })}
  end

  def handle_event(app, {:server_job, _ref, :cleanup_failed, _reason}), do: {:cont, app}

  def handle_event(app, {:git, snapshot}) when is_map(snapshot) do
    {:cont, app |> put_state(%{git: normalize_git(snapshot)}) |> sync_git_modal()}
  end

  @spec default_runner(String.t(), pid(), reference()) :: {:ok, pid()}
  def default_runner(command, notify, ref) do
    Command.start(command, notify, ref: ref)
  end

  @spec default_test_command() :: String.t()
  def default_test_command, do: Config.default_test_command()

  @spec default_server_command() :: String.t() | nil
  def default_server_command, do: %Config{}.server

  @doc false
  @spec default_server_runner(String.t(), pid(), reference()) :: {:ok, pid()} | {:error, term()}
  def default_server_runner(command, notify, ref) do
    ServerJob.start(command, notify, ref: ref)
  end

  @doc false
  def schedule_probe(message, delay), do: Process.send_after(self(), message, delay)

  @doc false
  def attach_keyboard(%{keys: :device} = app) do
    {:ok, pid} = Keyboard.start(app.device, self())
    %{app | keyboard: pid}
  end

  def attach_keyboard(app), do: app

  @doc false
  def attach_git(%{poll_git: true} = app) do
    git = Process.whereis(Tidex.Git)

    if git do
      Git.subscribe(self())
    end

    snapshot = normalize_git(app.git_reader.())
    %{app | git_pid: git, state: %{app.state | git: snapshot}}
  end

  def attach_git(app), do: app

  @doc false
  def shutdown(app) do
    Command.stop(app.state.test_pid)
    server_stop = app.server_stopper.(app.state.server_pid)
    Command.stop(app.state.git_cmd_pid)

    if app.git_pid == Process.whereis(Tidex.Git) do
      Git.unsubscribe(self())
    else
      Git.stop(app.git_pid)
    end

    Keyboard.stop(app.keyboard)
    Termex.show_cursor(app.device)
    Termex.clear_visible(app.device)
    Termex.move(app.device, 1, 1)

    message =
      case server_stop do
        :ok -> "tidex stopped\n"
        {:error, _reason} -> "tidex stopped; server cleanup failed\n"
      end

    Termex.write(app.device, message)
    :ok
  end

  defp start_tests(app) do
    app = app |> persist_visible() |> stop_tracked(:test) |> stop_git_cmd()
    ref = make_ref()
    {:ok, pid} = app.runner.(app.state.test_command, self(), ref)

    put_state(app, %{
      test_state: :running,
      test_ref: ref,
      test_pid: pid,
      test_log: [],
      failures: [],
      failure_index: 0,
      modal: nil
    })
  end

  defp start_or_restart_server(%{state: %{server_command: command}} = app)
       when not is_binary(command) or command == "",
       do: app

  defp start_or_restart_server(app) do
    app = app |> persist_visible() |> stop_git_cmd()
    owned? = is_pid(app.state.server_pid)

    case stop_server_job(app) do
      {:ok, app} ->
        case server_status_after_stop(app, owned?) do
          :listening when owned? -> put_state(app, %{server_state: :stop_failed})
          :listening -> put_state(app, %{server_state: :port_busy})
          _other -> start_server_job(app)
        end

      {:error, app} ->
        app
    end
  end

  defp stop_server(%{state: %{server_command: command}} = app)
       when not is_binary(command) or command == "",
       do: app

  defp stop_server(app) do
    owned? = is_pid(app.state.server_pid)

    case stop_server_job(app) do
      {:ok, app} ->
        case server_status_after_stop(app, owned?) do
          :listening when owned? -> put_state(app, %{server_state: :stop_failed})
          :listening -> put_state(app, %{server_state: :port_busy})
          _other -> put_state(app, %{server_state: :down})
        end

      {:error, app} ->
        app
    end
  end

  defp start_server_job(app) do
    ref = make_ref()

    case app.server_runner.(app.state.server_command, self(), ref) do
      {:ok, pid} ->
        app
        |> put_state(%{
          overlay: nil,
          server_state: :starting,
          server_ref: ref,
          server_pid: pid,
          server_log: [],
          output_lines: [],
          output_source: nil
        })
        |> refresh_server_probe(ref)

      {:error, _reason} ->
        put_state(app, %{
          server_state: :start_failed,
          server_ref: nil,
          server_pid: nil
        })
    end
  end

  defp refresh_server_probe(%{state: %{server_ref: ref}} = app, ref) when is_reference(ref) do
    case app.server_probe.(app.state.browser_url) do
      :listening ->
        schedule_server_probe(app, ref)
        put_state(app, %{server_state: :up})

      :closed ->
        schedule_server_probe(app, ref)
        put_state(app, %{server_state: :starting})

      :unsupported ->
        put_state(app, %{server_state: :up})
    end
  end

  defp refresh_server_probe(app, _ref), do: app

  defp schedule_server_probe(app, ref) do
    app.probe_scheduler.({:server_probe, ref}, @server_probe_interval)
    app
  end

  defp server_status_after_stop(app, true), do: app.server_waiter.(app.state.browser_url)
  defp server_status_after_stop(app, false), do: app.server_probe.(app.state.browser_url)

  defp stop_server_job(%{state: %{server_pid: nil}} = app) do
    {:ok, put_state(app, %{server_ref: nil})}
  end

  defp stop_server_job(app) do
    case app.server_stopper.(app.state.server_pid) do
      :ok ->
        {:ok, put_state(app, %{server_pid: nil, server_ref: nil})}

      {:error, _reason} ->
        {:error, put_state(app, %{server_state: :stop_failed})}
    end
  end

  defp launch_editor(app, opts \\ []) do
    app = detach_keyboard(app)

    Termex.yield(app.device, app.tty, fn ->
      app.editor_runner.(editor_command(app, opts))
    end)

    attach_keyboard(app)
  end

  defp open_fail_modal(app) do
    case Failures.modal(app.state) do
      nil -> app
      modal -> put_state(app, %{overlay: nil, modal: modal})
    end
  end

  defp close_fail_modal(app), do: put_state(app, %{modal: nil})

  defp cycle_fail_modal(app, delta) do
    state = Failures.cycle(app.state, delta)
    put_state(app, %{failure_index: state.failure_index, modal: Failures.modal(state)})
  end

  defp sync_fail_modal(%{state: %{modal: %{kind: :fail}}} = app) do
    put_state(app, %{modal: Failures.modal(app.state)})
  end

  defp sync_fail_modal(app), do: app

  defp editor_command(app, opts) do
    {file, line} =
      case Keyword.get(opts, :file) do
        path when is_binary(path) and path != "" ->
          {path, Keyword.get(opts, :line)}

        _ ->
          target = Failures.current(app.state)
          {project_path(app.state, target && target.file), target && target.line}
      end

    Open.editor_command(app.state.editor_command, file: file, line: line)
  end

  defp open_listed_file(app, n) do
    case listed_path(app.state, n) do
      nil -> app
      path -> launch_editor(app, file: path)
    end
  end

  defp project_path(_state, path) when not is_binary(path) or path == "", do: nil

  defp project_path(state, path) do
    if Path.type(path) == :absolute, do: path, else: Path.expand(path, state.config_root)
  end

  defp listed_path(state, n) do
    case Map.get(state.files, n) do
      path when is_binary(path) and path != "" ->
        project_path(state, path)

      _ ->
        nil
    end
  end

  defp config_file(state) do
    state.config_path || Path.join(state.cwd, Config.filename())
  end

  defp git_add(app), do: start_git_cmd(app, "git add -u")

  defp git_push(app), do: start_git_cmd(app, "git push")

  defp git_commit(app) do
    app = detach_keyboard(app)

    Termex.yield(app.device, app.tty, fn ->
      app.editor_runner.("git commit")
    end)

    app
    |> attach_keyboard()
    |> put_state(%{git: normalize_git(app.git_reader.())})
    |> sync_git_modal()
  end

  defp start_git_cmd(app, command) do
    app = app |> persist_visible() |> stop_git_cmd()
    ref = make_ref()
    {:ok, pid} = app.runner.(command, self(), ref)

    app
    |> put_state(%{
      overlay: nil,
      git_cmd_ref: ref,
      git_cmd_pid: pid,
      git_log: [],
      output_lines: [],
      output_scroll: :follow,
      output_source: :git
    })
    |> sync_git_modal()
  end

  defp open_git_modal(app) do
    app = persist_visible(app)
    put_state(app, %{overlay: nil, modal: GitModal.modal(app.state)})
  end

  defp close_git_modal(app), do: app |> persist_visible() |> put_state(%{modal: nil})

  defp open_help_modal(app) do
    app
    |> persist_visible()
    |> put_state(%{overlay: nil, modal: Help.modal()})
  end

  defp close_help_modal(app), do: put_state(app, %{modal: nil})

  defp maybe_append_output(app, ref, line) do
    cond do
      app.state.test_ref == ref -> append_log(app, :test, line)
      app.state.server_ref == ref -> append_log(app, :server, line)
      app.state.git_cmd_ref == ref -> append_log(app, :git, line)
      true -> app
    end
  end

  defp finish_command(app, ref, status) do
    cond do
      app.state.test_ref == ref ->
        test_state = if status == 0, do: :pass, else: :fail

        failures =
          if status == 0,
            do: [],
            else: Failures.parse(log_lines(app.state, :test), app.state.test_format)

        put_state(app, %{
          test_state: test_state,
          test_ref: nil,
          test_pid: nil,
          failures: failures,
          failure_index: 0
        })
        |> sync_fail_modal()

      app.state.server_ref == ref ->
        app = put_state(app, %{server_ref: nil, server_pid: nil})

        case app.server_waiter.(app.state.browser_url) do
          :listening -> put_state(app, %{server_state: :stop_failed})
          _other -> put_state(app, %{server_state: :down})
        end

      app.state.git_cmd_ref == ref ->
        app
        |> put_state(%{
          git_cmd_ref: nil,
          git_cmd_pid: nil,
          git: normalize_git(app.git_reader.())
        })
        |> sync_git_modal()

      true ->
        app
    end
  end

  defp persist_visible(app) do
    case app.state.output_source do
      :test -> put_state(app, %{test_log: app.state.output_lines})
      :git -> put_state(app, %{git_log: app.state.output_lines})
      _ -> app
    end
  end

  defp append_log(app, source, line) do
    lines = log_lines(app.state, source) ++ [to_string(line)]
    changes = %{log_field(source) => lines}

    changes =
      if app.state.output_source == source do
        Map.put(changes, :output_lines, lines)
      else
        changes
      end

    app = put_state(app, changes)

    case source do
      :test -> refresh_test_failures(app)
      :git -> sync_git_modal(app)
      _ -> app
    end
  end

  defp refresh_test_failures(app) do
    failures = Failures.parse(log_lines(app.state, :test), app.state.test_format)
    n = length(failures)
    index = if n == 0, do: 0, else: rem(app.state.failure_index, n)

    put_state(app, %{failures: failures, failure_index: index})
    |> sync_fail_modal()
  end

  defp log_lines(state, source) do
    if state.output_source == source do
      state.output_lines
    else
      Map.fetch!(state, log_field(source))
    end
  end

  defp log_field(:test), do: :test_log
  defp log_field(:server), do: :server_log
  defp log_field(:git), do: :git_log

  defp sync_git_modal(%{state: %{modal: %{kind: :git, scroll: scroll}}} = app) do
    put_state(app, %{modal: GitModal.modal(app.state, scroll)})
  end

  defp sync_git_modal(%{state: %{modal: %{kind: :git_info}}} = app) do
    put_state(app, %{modal: GitInfo.modal(app.state.git)})
  end

  defp sync_git_modal(app), do: app

  defp stop_tracked(app, :test) do
    Command.stop(app.state.test_pid)
    put_state(app, %{test_pid: nil, test_ref: nil})
  end

  defp stop_git_cmd(app) do
    Command.stop(app.state.git_cmd_pid)
    put_state(app, %{git_cmd_pid: nil, git_cmd_ref: nil})
  end

  defp setup_write(app, :cwd) do
    case app.state.setup do
      %{offer_cwd: true, cwd: dir} -> do_setup_write(app, dir)
      _ -> app
    end
  end

  defp setup_write(app, :git) do
    case app.state.setup do
      %{offer_git: true, git_root: dir} when is_binary(dir) -> do_setup_write(app, dir)
      _ -> app
    end
  end

  defp do_setup_write(app, dir) do
    case Config.write!(dir, app.home) do
      {:ok, _} -> apply_config(app)
      {:error, _} -> app
    end
  end

  defp apply_config(app) do
    config = Config.load(app.state.cwd, app.home)
    path = Config.find_file(app.state.cwd, app.home)
    root = if is_binary(path), do: Path.dirname(path), else: app.state.cwd

    put_state(app, %{
      overlay: nil,
      setup: nil,
      project_name: config.project,
      test_command: config.test,
      test_format: config.test_format,
      server_command: config.server,
      browser_url: config.browser,
      editor_command: config.editor,
      files: config.files,
      config_path: path,
      config_root: root
    })
  end

  defp setup_skip(app) do
    put_state(app, %{overlay: nil, setup: nil})
  end

  defp normalize_git(snapshot) when is_map(snapshot) do
    %{
      branch: Map.get(snapshot, :branch),
      dirty: Map.get(snapshot, :dirty, 0),
      untracked: Map.get(snapshot, :untracked, 0),
      status: Map.get(snapshot, :status, "")
    }
  end

  defp detach_keyboard(app) do
    Keyboard.stop(app.keyboard)
    %{app | keyboard: nil}
  end

  defp put_state(app, changes) do
    %{app | state: struct(app.state, changes)}
  end

  defp dimensions(opts, dimension_reader) do
    {detected_width, detected_height} = dimension_reader.()
    width = Keyword.get(opts, :width) || detected_width
    height = Keyword.get(opts, :height) || detected_height
    {width, height}
  end

  @doc false
  @spec terminal_dimensions() :: {pos_integer(), pos_integer()}
  def terminal_dimensions, do: {detect_columns(), detect_rows()}

  defp detect_columns do
    case :io.columns() do
      {:ok, n} when is_integer(n) and n > 16 -> n
      _ -> 80
    end
  end

  defp detect_rows do
    case :io.rows() do
      {:ok, n} when is_integer(n) and n > 12 -> n
      _ -> 24
    end
  end
end
