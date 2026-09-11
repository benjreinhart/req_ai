defmodule ReqAI.ProviderTest do
  use ExUnit.Case, async: false

  alias ReqAI.{Provider, Telemetry}

  defmodule TestProvider do
    @behaviour Provider

    @impl true
    def build(req, _request, _opts), do: req

    @impl true
    def telemetry(_source, _opts), do: %{}
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
    assert provider.opts == [model: "test-model"]
    assert Req.Request.get_option(provider.req, :base_url) == "https://options.example"
    assert Req.Request.get_option(provider.req, :retry) == false
    assert Req.Request.get_header(provider.req, "x-config") == ["configured"]
    assert Req.Request.get_header(provider.req, "x-option") == ["passed"]
    assert Req.Request.get_header(provider.req, "x-shared") == ["passed"]
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
      assert Telemetry.request_metadata(provider, %{model: "request-model"}, stream: false) ==
               %{
                 "gen_ai.operation.name": operation_name,
                 "gen_ai.provider.name": provider_name,
                 "gen_ai.request.model": "request-model"
               }

      assert Telemetry.request_metadata(provider, %{}, stream: true) == %{
               "gen_ai.operation.name": operation_name,
               "gen_ai.provider.name": provider_name,
               "gen_ai.request.stream": true
             }

      response = Req.Response.new(status: 200, body: %{"model" => "response-model"})

      assert Telemetry.response_metadata(provider, %{}, response, [], false) == %{
               "gen_ai.response.model": "response-model",
               "http.response.status_code": 200,
               error: false
             }

      response = Req.Response.new(status: 200, body: %{})

      assert Telemetry.response_metadata(provider, %{}, response, [], false) == %{
               "http.response.status_code": 200,
               error: false
             }
    end)
  end
end
