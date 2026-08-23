defmodule ReqAI.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_ai,
      version: "0.1.0",
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
      {:req, "0.8.0-rc.0"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      description: "Req-powered, lightweight runtime for provider-native LLM APIs.",
      links: %{"GitHub" => "https://github.com/benjreinhart/req_ai"}
    ]
  end
end
