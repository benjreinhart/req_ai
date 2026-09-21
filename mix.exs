defmodule ReqAI.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_ai,
      version: "0.0.1-alpha.1",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:req, "0.8.0-rc.0"},
      {:telemetry, "~> 1.3"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      description: "Req-based LLM client with streaming, telemetry, and provider-native data.",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/benjreinhart/req_ai"}
    ]
  end
end
