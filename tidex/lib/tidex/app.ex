defmodule Tidex.App do
  @moduledoc """
  Tidex's UI process: render, wait for an event, update, repeat.

  Keyboard input arrives as messages so command output can stream in
  without blocking on a key read. Background command and git processes
  never draw; this process owns the screen.
  """

  alias Tidex.{Command, Config, Git, Open, State, View}

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
    config = Keyword.get(opts, :config) || Config.load()

    state = %State{
      title: Keyword.get(opts, :title, "Tidex"),
      project_name: Keyword.get(opts, :project_name, "exmex-talk"),
      test_command: Keyword.get(opts, :test_command, config.test),
      server_command: Keyword.get(opts, :server_command, config.server),
      browser_url: Keyword.get(opts, :browser_url, config.browser),
      editor_command: Keyword.get(opts, :editor_command, config.editor),
      git: Keyword.get(opts, :git, %{branch: nil, dirty: 0}),
      layout: Keyword.get(opts, :layout, :dashboard),
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
    start(new(opts))
  end

  def start(%__MODULE__{} = app) do
    Termex.with_raw_mode(app.device, fn session ->
      app =
        app
        |> Map.put(:tty, session)
        |> attach_keyboard()
        |> attach_git()

      View.render(app.device, app.state)

      if is_pid(app.notify_ready) do
        send(app.notify_ready, {:ready, self()})
      end

      loop(app)
    end)
  end

  @spec loop(t()) :: :ok
  def loop(%__MODULE__{} = app) do
    receive do
      {:termex, :key, key} ->
        dispatch(app, {:key, key})

      {:command, ref, :line, line} ->
        dispatch(app, {:command, ref, :line, line})

      {:command, ref, :exit, status} ->
        dispatch(app, {:command, ref, :exit, status})

      {:git, snapshot} ->
        dispatch(app, {:git, snapshot})
    end
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

  def handle_event(app, {:key, _key}), do: {:cont, app}

  def handle_event(app, {:command, ref, :line, line}) do
    {:cont, maybe_append_output(app, ref, line)}
  end

  def handle_event(app, {:command, ref, :exit, status}) do
    {:cont, finish_command(app, ref, status)}
  end

  def handle_event(app, {:git, snapshot}) when is_map(snapshot) do
    {:cont, put_state(app, %{git: snapshot})}
  end

  @spec default_runner(String.t(), pid(), reference()) :: {:ok, pid()}
  def default_runner(command, notify, ref) do
    Command.start(command, notify, ref: ref)
  end

  @spec default_test_command() :: String.t()
  def default_test_command, do: Config.default_test_command()

  @spec default_server_command() :: String.t()
  def default_server_command, do: %Config{}.server

  defp dispatch(app, event) do
    case step(app, event) do
      {:quit, app} -> halt(app)
      {:cont, app} -> loop(app)
    end
  end

  defp start_tests(app) do
    app = stop_tracked(app, :test)
    ref = make_ref()
    {:ok, pid} = app.runner.(app.state.test_command, self(), ref)

    put_state(app, %{
      test_state: :running,
      test_ref: ref,
      test_pid: pid,
      output_lines: [],
      output_source: :test
    })
  end

  defp start_or_restart_server(app) do
    app = stop_tracked(app, :server)
    ref = make_ref()
    {:ok, pid} = app.runner.(app.state.server_command, self(), ref)

    put_state(app, %{
      server_state: :up,
      server_ref: ref,
      server_pid: pid,
      output_lines: [],
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
      app.editor_runner.(app.state.editor_command)
    end)

    attach_keyboard(app)
  end

  defp toggle_layout(app) do
    next = if app.state.layout == :dashboard, do: :output, else: :dashboard
    put_state(app, %{layout: next})
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
        put_state(app, %{test_state: test_state, test_ref: nil, test_pid: nil})

      app.state.server_ref == ref ->
        put_state(app, %{server_state: :down, server_ref: nil, server_pid: nil})

      true ->
        app
    end
  end

  defp active_ref?(app, ref) do
    (app.state.output_source == :test and app.state.test_ref == ref) or
      (app.state.output_source == :server and app.state.server_ref == ref)
  end

  defp stop_tracked(app, :test) do
    Command.stop(app.state.test_pid)
    put_state(app, %{test_pid: nil, test_ref: nil})
  end

  defp stop_tracked(app, :server) do
    Command.stop(app.state.server_pid)
    put_state(app, %{server_pid: nil, server_ref: nil})
  end

  defp attach_keyboard(%{keys: :device} = app) do
    {:ok, pid} = Termex.keyboard(app.device, notify: self())
    %{app | keyboard: pid}
  end

  defp attach_keyboard(app), do: app

  defp detach_keyboard(app) do
    if is_pid(app.keyboard) and Process.alive?(app.keyboard) do
      Process.exit(app.keyboard, :kill)
    end

    %{app | keyboard: nil}
  end

  defp attach_git(%{poll_git: true} = app) do
    {:ok, pid} = Git.start_link(self(), reader: app.git_reader, interval: 2000)
    snapshot = app.git_reader.()
    %{app | git_pid: pid, state: %{app.state | git: snapshot}}
  end

  defp attach_git(app), do: app

  defp put_state(app, changes) do
    %{app | state: struct(app.state, changes)}
  end

  defp halt(app) do
    Command.stop(app.state.test_pid)
    Command.stop(app.state.server_pid)
    Git.stop(app.git_pid)
    _ = detach_keyboard(app)
    Termex.clear_visible(app.device)
    Termex.move(app.device, 1, 1)
    Termex.write(app.device, "tidex stopped\n")
    :ok
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
