defmodule Tidex.App do
  @moduledoc """
  Tidex's UI process: render, wait for a key, update, repeat.

  Background monitors are not here yet. The next Termex feature should
  come from the next concrete Tidex need, not from this loop.
  """

  alias Tidex.{State, View}

  defstruct device: nil,
            state: %State{},
            runner: &Tidex.App.default_runner/1

  @type t :: %__MODULE__{
          device: Termex.Device.t(),
          state: State.t(),
          runner: (String.t() -> {String.t(), non_neg_integer()})
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    state = %State{
      title: Keyword.get(opts, :title, "Tidex"),
      project_name: Keyword.get(opts, :project_name, "exmex-talk"),
      statuses: Keyword.get(opts, :statuses, [{"tests", "idle"}, {"git", "idle"}]),
      command: Keyword.get(opts, :command, "echo hello from tidex")
    }

    %__MODULE__{
      device: Keyword.get(opts, :device, Termex.Device.stdio()),
      state: state,
      runner: Keyword.get(opts, :runner, &default_runner/1)
    }
  end

  @doc """
  Draw the dashboard and process keys until quit.

  Uses Termex raw mode when stdin is a TTY; tests inject a device and
  skip that path.
  """
  @spec start(keyword() | t()) :: :ok
  def start(opts_or_app \\ [])

  def start(opts) when is_list(opts) do
    start(new(opts))
  end

  def start(%__MODULE__{} = app) do
    Termex.with_raw_mode(app.device, fn -> run(app) end)
  end

  @spec run(t()) :: :ok
  def run(%__MODULE__{} = app) do
    View.render(app.device, app.state)

    case Termex.read_key(app.device) do
      :eof ->
        halt(app)

      key ->
        case handle_key(app, key) do
          {:quit, app} -> halt(app)
          {:cont, app} -> run(app)
        end
    end
  end

  @spec handle_key(t(), String.t()) :: {:cont, t()} | {:quit, t()}
  def handle_key(app, key) when key in ["q", "Q", <<3>>], do: {:quit, app}

  def handle_key(app, "t"), do: {:cont, run_command(app)}
  def handle_key(app, "T"), do: {:cont, run_command(app)}

  def handle_key(app, _key), do: {:cont, app}

  @spec default_runner(String.t()) :: {String.t(), non_neg_integer()}
  def default_runner(command) do
    System.cmd("sh", ["-c", command], stderr_to_stdout: true)
  end

  defp run_command(%__MODULE__{} = app) do
    {output, status} = app.runner.(app.state.command)
    %{app | state: %{app.state | command_output: output, last_status: status}}
  end

  defp halt(app) do
    Termex.clear_visible(app.device)
    Termex.move(app.device, 1, 1)
    Termex.write(app.device, "tidex stopped\n")
    :ok
  end
end
