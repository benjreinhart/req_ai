defmodule ReqAI.ProviderTest do
  use ExUnit.Case, async: false

  alias ReqAI.Provider

  defmodule TestProvider do
    @behaviour Provider

    @impl true
    def build(req, _request, _opts), do: req
  end

  defmodule TestTranslator do
    @behaviour ReqAI.Translator
  end

  test "merges application config with options passed to new/2" do
    previous_providers = Application.fetch_env(:req_ai, :providers)
    providers = Application.get_env(:req_ai, :providers, [])

    Application.put_env(
      :req_ai,
      :providers,
      Keyword.put(providers, TestProvider,
        req: [
          base_url: "https://config.example",
          headers: [{"x-config", "configured"}, {"x-shared", "configured"}],
          retry: false
        ]
      )
    )

    on_exit(fn ->
      case previous_providers do
        {:ok, providers} -> Application.put_env(:req_ai, :providers, providers)
        :error -> Application.delete_env(:req_ai, :providers)
      end
    end)

    provider =
      Provider.new(TestProvider,
        req: [
          base_url: "https://options.example",
          headers: [{"x-option", "passed"}, {"x-shared", "passed"}]
        ],
        translator: TestTranslator,
        model: "test-model"
      )

    assert provider.module == TestProvider
    assert provider.translator == TestTranslator
    assert provider.telemetry == TestProvider
    assert provider.telemetry_metadata == %{}
    assert provider.opts == [model: "test-model"]
    assert Req.Request.get_option(provider.req, :base_url) == "https://options.example"
    assert Req.Request.get_option(provider.req, :retry) == false
    assert Req.Request.get_header(provider.req, "x-config") == ["configured"]
    assert Req.Request.get_header(provider.req, "x-option") == ["passed"]
    assert Req.Request.get_header(provider.req, "x-shared") == ["passed"]
  end

  test "configures telemetry separately from provider options" do
    provider =
      Provider.new(TestProvider,
        telemetry: false,
        telemetry_metadata: %{feature: :summarizer},
        model: "test-model"
      )

    assert provider.telemetry == false
    assert provider.telemetry_metadata == %{feature: :summarizer}
    assert provider.opts == [model: "test-model"]
  end

  test "built-in providers return request and response telemetry" do
    providers = [
      {ReqAI.Provider.Anthropic, "anthropic", "chat"},
      {ReqAI.Provider.Gemini, "gcp.gemini", "generate_content"},
      {ReqAI.Provider.OpenAI, "openai", "chat"},
      {ReqAI.Provider.OpenRouter, "openrouter", "chat"},
      {ReqAI.Provider.XAI, "x_ai", "chat"}
    ]

    Enum.each(providers, fn {provider, provider_name, operation_name} ->
      assert provider.request_metadata(
               %{feature: :summarizer, "gen_ai.request.stream": true},
               %{model: "request-model"},
               stream: false
             ) == %{
               "gen_ai.operation.name": operation_name,
               "gen_ai.provider.name": provider_name,
               "gen_ai.request.model": "request-model",
               "gen_ai.request.stream": true,
               feature: :summarizer
             }

      assert provider.request_metadata(%{}, %{}, stream: true) == %{
               "gen_ai.operation.name": operation_name,
               "gen_ai.provider.name": provider_name,
               "gen_ai.request.model": nil
             }

      response = Req.Response.new(status: 200, body: %{"model" => "response-model"})

      assert provider.response_metadata(%{feature: :summarizer}, response, []) == %{
               "gen_ai.response.model": "response-model",
               feature: :summarizer
             }

      response = Req.Response.new(status: 200, body: %{})

      assert provider.response_metadata(%{}, response, []) == %{"gen_ai.response.model": nil}
    end)
  end
end
