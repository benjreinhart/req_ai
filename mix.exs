defmodule ReqAI.MixProject do
  use Mix.Project

  @version "0.0.1-alpha.2"
  @source_url "https://github.com/benjreinhart/req_ai"

  def project do
    [
      app: :req_ai,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
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
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "guides/getting-started.md"],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: ~r/^guides\//
      ],
      groups_for_modules: [
        Core: [ReqAI, ReqAI.Provider],
        Extension: [ReqAI.Translator, ReqAI.Telemetry],
        Providers: ~r/^ReqAI\.Provider\./
      ]
    ]
  end
end
