defmodule Tidex.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Tidex.ExecPort, []},
      {DynamicSupervisor, name: Tidex.Workers, strategy: :one_for_one},
      {Tidex.Git, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Tidex.Supervisor)
  end
end
