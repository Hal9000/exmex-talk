defmodule Tidex.UI do
  @moduledoc """
  Supervised UI process. Owns rendering and coordinates messages from
  the keyboard, git poller, and command jobs.
  """

  use GenServer

  alias Tidex.{App, Resize, View}

  @spec run(keyword() | App.t()) :: :ok
  def run(opts_or_app) do
    {:ok, pid} = start_link(opts_or_app)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end

  @spec start_link(keyword() | App.t()) :: GenServer.on_start()
  def start_link(opts_or_app) do
    opts = if is_list(opts_or_app), do: opts_or_app, else: []
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts_or_app, name_opts(name))
  end

  @impl GenServer
  def init(opts_or_app) do
    app = if is_list(opts_or_app), do: App.new(opts_or_app), else: opts_or_app
    {:ok, session} = Termex.enter(app.device)
    {:ok, %{app | tty: session}, {:continue, :boot}}
  end

  @impl GenServer
  def handle_continue(:boot, app) do
    app =
      app
      |> App.attach_keyboard()
      |> App.attach_git()
      |> attach_resize()
      |> App.refresh_dimensions()

    View.render(app.device, app.state)

    if is_pid(app.notify_ready) do
      send(app.notify_ready, {:ready, self()})
    end

    {:noreply, app}
  end

  @impl GenServer
  def handle_info({:termex, :key, key}, app), do: dispatch(app, {:key, key})

  def handle_info({:command, ref, :line, line}, app),
    do: dispatch(app, {:command, ref, :line, line})

  def handle_info({:command, ref, :exit, status}, app),
    do: dispatch(app, {:command, ref, :exit, status})

  def handle_info({:server_probe, ref}, app), do: dispatch(app, {:server_probe, ref})

  def handle_info({:server_job, ref, :cleanup_failed, reason}, app),
    do: dispatch(app, {:server_job, ref, :cleanup_failed, reason})

  def handle_info({:git, snapshot}, app), do: dispatch(app, {:git, snapshot})

  def handle_info(:sigwinch, app) do
    app = App.refresh_dimensions(app)
    View.render(app.device, app.state)
    {:noreply, app}
  end

  def handle_info(_other, app), do: {:noreply, app}

  @impl GenServer
  def terminate(_reason, app) do
    Resize.unsubscribe(app.resize_handler)
    App.shutdown(app)
    Termex.leave(app.tty)
    :ok
  end

  defp dispatch(app, event) do
    case App.step(app, event) do
      {:cont, app} -> {:noreply, app}
      {:quit, app} -> {:stop, :normal, app}
    end
  end

  defp name_opts(nil), do: []
  defp name_opts(name), do: [name: name]

  defp attach_resize(%{resize: false} = app), do: app

  defp attach_resize(app) do
    case Resize.subscribe(self()) do
      {:ok, handler} -> %{app | resize_handler: handler}
      {:error, _reason} -> app
    end
  end
end
