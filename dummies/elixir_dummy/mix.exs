defmodule Dummy.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_dummy,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Dummy.Application, []}
    ]
  end

  defp deps do
    [
      {:cowboy, "~> 2.4"},
      {:distillery, "~> 2.0.0-rc.8"}
    ]
  end
end
