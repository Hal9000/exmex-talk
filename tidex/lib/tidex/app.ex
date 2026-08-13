defmodule Tidex.App do
  @moduledoc """
  Tidex's UI process: render, wait for an event, update, repeat.

  Keyboard input arrives as messages so command output can stream in
  without blocking on a key read. Background command processes own the
  ports; this process owns the screen.
  """

  alias Tidex.{Command, State, View}

  defstruct device: nil,
            state: %State{},
            runner: &Tidex.App.default_runner/3,
            keys: :device,
            notify_ready: nil

  @type t :: %__MODULE__{
          device: Termex.Device.t(),
          state: State.t(),
          runner: (String.t(), pid(), reference() -> {:ok, pid()}),
          keys: :device | :none,
          notify_ready: pid() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    {width, height} = dimensions(opts)

    state = %State{
      title: Keyword.get(opts, :title, "Tidex"),
      project_name: Keyword.get(opts, :project_name, "exmex-talk"),
      test_command: Keyword.get(opts, :test_command, default_test_command()),
      server_command: Keyword.get(opts, :server_command, default_server_command()),
      width: width,
      height: height
    }

    %__MODULE__{
      device: Keyword.get(opts, :device, Termex.Device.stdio()),
      state: state,
      runner: Keyword.get(opts, :runner, &default_runner/3),
      keys: Keyword.get(opts, :keys, :device),
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
    Termex.with_raw_mode(app.device, fn ->
      if app.keys == :device do
        {:ok, _} = Termex.keyboard(app.device, notify: self())
      end

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

  def handle_event(app, {:key, _key}), do: {:cont, app}

  def handle_event(app, {:command, ref, :line, line}) do
    {:cont, maybe_append_output(app, ref, line)}
  end

  def handle_event(app, {:command, ref, :exit, status}) do
    {:cont, finish_command(app, ref, status)}
  end

  @spec default_runner(String.t(), pid(), reference()) :: {:ok, pid()}
  def default_runner(command, notify, ref) do
    Command.start(command, notify, ref: ref)
  end

  @spec default_test_command() :: String.t()
  def default_test_command do
    cond do
      File.exists?("mix.exs") -> "mix test"
      File.exists?("package.json") -> "npm test"
      File.exists?("Cargo.toml") -> "cargo test"
      File.exists?("go.mod") -> "go test ./..."
      true -> "echo no test runner found"
    end
  end

  @spec default_server_command() :: String.t()
  def default_server_command do
    "python3 -m http.server 4000"
  end

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
      server_state: :running,
      server_ref: ref,
      server_pid: pid,
      output_lines: [],
      output_source: :server
    })
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
        put_state(app, %{server_state: :stopped, server_ref: nil, server_pid: nil})

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

  defp put_state(app, changes) do
    %{app | state: struct(app.state, changes)}
  end

  defp halt(app) do
    Command.stop(app.state.test_pid)
    Command.stop(app.state.server_pid)
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
