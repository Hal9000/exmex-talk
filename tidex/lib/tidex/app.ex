defmodule Tidex.App do
  @moduledoc """
  Tidex's UI process: render, wait for an event, update, repeat.

  Keyboard input arrives as messages so command output can stream in
  without blocking on a key read. Background command and git processes
  never draw; this process owns the screen.
  """

  alias Tidex.{Command, Config, Failures, Git, Keyboard, Layout, Open, Scroll, Setup, State, View}

  defstruct device: nil,
            state: %State{},
            runner: &Tidex.App.default_runner/3,
            editor_runner: &Open.editor/1,
            browser_runner: &Open.browser/1,
            git_reader: &Git.snapshot/0,
            keys: :device,
            poll_git: false,
            notify_ready: nil,
            tty: nil,
            keyboard: nil,
            git_pid: nil

  @type t :: %__MODULE__{
          device: Termex.Device.t(),
          state: State.t(),
          runner: (String.t(), pid(), reference() -> {:ok, pid()}),
          editor_runner: (String.t() -> term()),
          browser_runner: (String.t() -> term()),
          git_reader: (-> Git.snapshot()),
          keys: :device | :none,
          poll_git: boolean(),
          notify_ready: pid() | nil,
          tty: Termex.RawMode.session(),
          keyboard: pid() | nil,
          git_pid: pid() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    {width, height} = dimensions(opts)
    cwd = Path.expand(Keyword.get(opts, :cwd, File.cwd!()))
    injected? = Keyword.has_key?(opts, :config)
    config = Keyword.get(opts, :config) || Config.load(cwd)

    setup =
      cond do
        injected? -> nil
        Setup.needed?(cwd) -> Setup.probe(cwd)
        true -> nil
      end

    state = %State{
      title: Keyword.get(opts, :title, "Tidex"),
      project_name: Keyword.get(opts, :project_name, config.project),
      test_command: Keyword.get(opts, :test_command, config.test),
      server_command: Keyword.get(opts, :server_command, config.server),
      browser_url: Keyword.get(opts, :browser_url, config.browser),
      editor_command: Keyword.get(opts, :editor_command, config.editor),
      git: Keyword.get(opts, :git, %{branch: nil, dirty: 0, status: ""}),
      layout: Keyword.get(opts, :layout, :dashboard),
      overlay: if(setup, do: :setup, else: nil),
      setup: setup,
      cwd: cwd,
      width: width,
      height: height
    }

    %__MODULE__{
      device: Keyword.get(opts, :device, Termex.Device.stdio()),
      state: state,
      runner: Keyword.get(opts, :runner, &default_runner/3),
      editor_runner: Keyword.get(opts, :editor_runner, &Open.editor/1),
      browser_runner: Keyword.get(opts, :browser_runner, &Open.browser/1),
      git_reader: Keyword.get(opts, :git_reader, &Git.snapshot/0),
      keys: Keyword.get(opts, :keys, :device),
      poll_git: Keyword.get(opts, :poll_git, false),
      notify_ready: Keyword.get(opts, :notify_ready)
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
    case handle_event(app, event) do
      {:cont, app} ->
        View.render(app.device, app.state)
        {:cont, app}

      {:quit, app} ->
        {:quit, app}
    end
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

  def handle_event(app, {:key, "?"}) do
    next = if app.state.overlay == :help, do: nil, else: :help
    {:cont, put_state(app, %{overlay: next})}
  end

  def handle_event(app, {:key, "g"}) do
    next = if app.state.overlay == :git, do: nil, else: :git
    {:cont, put_state(app, %{overlay: next})}
  end

  def handle_event(%{state: %{overlay: overlay}} = app, {:key, :esc}) when overlay != nil do
    {:cont, put_state(app, %{overlay: nil})}
  end

  def handle_event(%{state: %{overlay: :git}} = app, {:key, key}) when key in ["a", "A"] do
    {:cont, git_add(app)}
  end

  def handle_event(%{state: %{overlay: :git}} = app, {:key, key}) when key in ["c", "C"] do
    {:cont, git_commit(app)}
  end

  def handle_event(%{state: %{overlay: :git}} = app, {:key, key}) when key in ["p", "P"] do
    {:cont, git_push(app)}
  end

  def handle_event(%{state: %{overlay: overlay}} = app, {:key, _key}) when overlay != nil do
    {:cont, app}
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

  def handle_event(app, {:key, key}) when key in ["b", "B"] do
    app.browser_runner.(app.state.browser_url)
    {:cont, app}
  end

  def handle_event(app, {:key, key}) when key in ["e", "E"] do
    {:cont, launch_editor(app)}
  end

  def handle_event(app, {:key, key}) when key in ["l", "L"] do
    {:cont, toggle_layout(app)}
  end

  def handle_event(app, {:key, key}) when key in [:up, :down, :page_up, :page_down] do
    {:cont, scroll_output(app, key)}
  end

  def handle_event(app, {:key, :left}) do
    {:cont, put_state(app, Failures.cycle(app.state, -1))}
  end

  def handle_event(app, {:key, :right}) do
    {:cont, put_state(app, Failures.cycle(app.state, 1))}
  end

  def handle_event(app, {:key, _key}), do: {:cont, app}

  def handle_event(app, {:command, ref, :line, line}) do
    {:cont, maybe_append_output(app, ref, line)}
  end

  def handle_event(app, {:command, ref, :exit, status}) do
    {:cont, finish_command(app, ref, status)}
  end

  def handle_event(app, {:git, snapshot}) when is_map(snapshot) do
    {:cont, put_state(app, %{git: normalize_git(snapshot)})}
  end

  @spec default_runner(String.t(), pid(), reference()) :: {:ok, pid()}
  def default_runner(command, notify, ref) do
    Command.start(command, notify, ref: ref)
  end

  @spec default_test_command() :: String.t()
  def default_test_command, do: Config.default_test_command()

  @spec default_server_command() :: String.t()
  def default_server_command, do: %Config{}.server

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
    Command.stop(app.state.server_pid)
    Command.stop(app.state.git_cmd_pid)

    if app.git_pid == Process.whereis(Tidex.Git) do
      Git.unsubscribe(self())
    else
      Git.stop(app.git_pid)
    end

    Keyboard.stop(app.keyboard)
    Termex.clear_visible(app.device)
    Termex.move(app.device, 1, 1)
    Termex.write(app.device, "tidex stopped\n")
    :ok
  end

  defp start_tests(app) do
    app = app |> stop_tracked(:test) |> stop_git_cmd()
    ref = make_ref()
    {:ok, pid} = app.runner.(app.state.test_command, self(), ref)

    put_state(app, %{
      test_state: :running,
      test_ref: ref,
      test_pid: pid,
      output_lines: [],
      output_scroll: :follow,
      output_source: :test,
      failures: [],
      failure_index: 0
    })
  end

  defp start_or_restart_server(app) do
    app = app |> stop_tracked(:server) |> stop_git_cmd()
    ref = make_ref()
    {:ok, pid} = app.runner.(app.state.server_command, self(), ref)

    put_state(app, %{
      server_state: :up,
      server_ref: ref,
      server_pid: pid,
      output_lines: [],
      output_scroll: :follow,
      output_source: :server
    })
  end

  defp stop_server(app) do
    app
    |> stop_tracked(:server)
    |> put_state(%{server_state: :down})
  end

  defp launch_editor(app) do
    app = detach_keyboard(app)

    Termex.yield(app.device, app.tty, fn ->
      app.editor_runner.(editor_command(app))
    end)

    attach_keyboard(app)
  end

  defp editor_command(app) do
    target = Failures.current(app.state)

    Open.editor_command(app.state.editor_command,
      file: target && target.file,
      line: target && target.line
    )
  end

  defp git_add(app), do: start_git_cmd(app, "git add -u")

  defp git_push(app), do: start_git_cmd(app, "git push")

  defp git_commit(app) do
    app = put_state(app, %{overlay: nil})
    app = detach_keyboard(app)

    Termex.yield(app.device, app.tty, fn ->
      app.editor_runner.("git commit")
    end)

    app
    |> attach_keyboard()
    |> put_state(%{git: normalize_git(app.git_reader.())})
  end

  defp start_git_cmd(app, command) do
    app = stop_git_cmd(app)
    ref = make_ref()
    {:ok, pid} = app.runner.(command, self(), ref)

    put_state(app, %{
      overlay: nil,
      git_cmd_ref: ref,
      git_cmd_pid: pid,
      output_lines: [],
      output_scroll: :follow,
      output_source: :git
    })
  end

  defp toggle_layout(app) do
    next = if app.state.layout == :dashboard, do: :output, else: :dashboard
    put_state(app, %{layout: next})
  end

  defp scroll_output(app, key) do
    height = output_inner_height(app.state)
    delta = scroll_delta(key, height)

    put_state(app, %{
      output_scroll: Scroll.step(app.state.output_lines, height, app.state.output_scroll, delta)
    })
  end

  defp scroll_delta(:up, _height), do: -1
  defp scroll_delta(:down, _height), do: 1
  defp scroll_delta(:page_up, height), do: -max(height, 1)
  defp scroll_delta(:page_down, height), do: max(height, 1)

  defp output_inner_height(state) do
    layout = Layout.compute(state)
    Layout.inner(layout.output).height
  end

  defp maybe_append_output(app, ref, line) do
    if active_ref?(app, ref) do
      put_state(app, %{output_lines: app.state.output_lines ++ [to_string(line)]})
    else
      app
    end
  end

  defp finish_command(app, ref, status) do
    cond do
      app.state.test_ref == ref ->
        test_state = if status == 0, do: :pass, else: :fail
        failures = if status == 0, do: [], else: Failures.parse(app.state.output_lines)

        put_state(app, %{
          test_state: test_state,
          test_ref: nil,
          test_pid: nil,
          failures: failures,
          failure_index: 0
        })

      app.state.server_ref == ref ->
        put_state(app, %{server_state: :down, server_ref: nil, server_pid: nil})

      app.state.git_cmd_ref == ref ->
        put_state(app, %{
          git_cmd_ref: nil,
          git_cmd_pid: nil,
          git: normalize_git(app.git_reader.())
        })

      true ->
        app
    end
  end

  defp active_ref?(app, ref) do
    (app.state.output_source == :test and app.state.test_ref == ref) or
      (app.state.output_source == :server and app.state.server_ref == ref) or
      (app.state.output_source == :git and app.state.git_cmd_ref == ref)
  end

  defp stop_tracked(app, :test) do
    Command.stop(app.state.test_pid)
    put_state(app, %{test_pid: nil, test_ref: nil})
  end

  defp stop_tracked(app, :server) do
    Command.stop(app.state.server_pid)
    put_state(app, %{server_pid: nil, server_ref: nil})
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
    case Config.write!(dir) do
      {:ok, _} -> apply_config(app)
      {:error, _} -> app
    end
  end

  defp apply_config(app) do
    config = Config.load(app.state.cwd)

    put_state(app, %{
      overlay: nil,
      setup: nil,
      project_name: config.project,
      test_command: config.test,
      server_command: config.server,
      browser_url: config.browser,
      editor_command: config.editor
    })
  end

  defp setup_skip(app) do
    put_state(app, %{overlay: nil, setup: nil})
  end

  defp normalize_git(snapshot) when is_map(snapshot) do
    %{
      branch: Map.get(snapshot, :branch),
      dirty: Map.get(snapshot, :dirty, 0),
      status: Map.get(snapshot, :status, "")
    }
  end

  defp detach_keyboard(app) do
    Keyboard.stop(app.keyboard)
    %{app | keyboard: nil}
  end

  defp put_state(app, %State{} = state), do: %{app | state: state}

  defp put_state(app, changes) do
    %{app | state: struct(app.state, changes)}
  end

  defp dimensions(opts) do
    width = Keyword.get(opts, :width) || detect_columns()
    height = Keyword.get(opts, :height) || detect_rows()
    {width, height}
  end

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
