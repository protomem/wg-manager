defmodule WGM.MixProject do
  use Mix.Project

  def project do
    [
      app: :wgm,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      releases: releases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WGM.Application, []}
    ]
  end

  defp releases do
    [
      wgm: [
        include_executables_for: [:unix],
        applications: [
          wgm: :permanent,
          runtime_tools: :permanent
        ],
        steps: [:assemble, :tar]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exqlite, "~> 0.29"},
      {:eqrcode, "~> 0.2"}
    ]
  end
end
