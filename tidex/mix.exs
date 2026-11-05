defmodule Tidex.MixProject do
  use Mix.Project

  def project do
    [
      app: :tidex,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      escript: [main_module: Tidex.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Tidex.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:erlexec, "~> 2.6"},
      {:termex, path: "../termex"}
    ]
  end
end
