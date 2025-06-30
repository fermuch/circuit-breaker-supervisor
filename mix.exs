defmodule CircuitBreakerSupervisor.MixProject do
  use Mix.Project

  @source_url "https://github.com/notslang/circuit-breaker-supervisor"

  def project do
    [
      app: :circuit_breaker_supervisor,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      deps: deps(),

      # Hex
      package: package(),
      description: """
      An Elixir supervisor implementation, where failed processes trip a circuit breaker.
      """,

      # Docs
      name: "Circuit Breaker Supervisor",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: &docs/0
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      formatters: ["html"]
    ]
  end

  defp package do
    [
      maintainers: ["Sean Lang"],
      licenses: ["MIT"],
      files: ~w(lib mix.exs README* CHANGELOG* LICENSE*),
      links: %{"GitHub" => @source_url}
    ]
  end
end
