defmodule ReqAI.ProviderTest do
  use ExUnit.Case, async: false

  alias ReqAI.Provider

  defmodule TestProvider do
    @behaviour Provider

    @impl true
    def build(req, _request, _opts), do: req

    @impl true
    def decode_event(event, _response, _opts), do: [event]
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

  test "built-in providers convert keyword request bodies to JSON object maps" do
    for provider <- [
          ReqAI.Provider.Anthropic,
          ReqAI.Provider.Gemini,
          ReqAI.Provider.OpenAI,
          ReqAI.Provider.OpenRouter,
          ReqAI.Provider.XAI
        ] do
      request = provider.build(Req.new(), [model: "test-model", stream: true], stream: false)

      assert request.options[:json] == %{model: "test-model", stream: false}
    end
  end

  test "built-in providers reject request lists that are not keyword lists" do
    assert_raise ArgumentError,
                 "expected a request map or keyword list, got: [\"not a keyword entry\"]",
                 fn ->
                   ReqAI.Provider.OpenAI.build(
                     Req.new(),
                     ["not a keyword entry"],
                     stream: false
                   )
                 end
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
               %{feature: :summarizer, stream: true},
               %{model: "request-model"},
               stream: false
             ) == %{
               operation: operation_name,
               provider: provider_name,
               model: "request-model",
               stream: true,
               feature: :summarizer
             }

      assert provider.request_metadata(%{}, %{}, stream: true) == %{
               operation: operation_name,
               provider: provider_name
             }

      response = Req.Response.new(status: 200, body: %{"model" => "response-model"})

      assert provider.response_metadata(%{feature: :summarizer}, response, []) == %{
               response_model: "response-model",
               feature: :summarizer
             }

      response = Req.Response.new(status: 200, body: %{})

      assert provider.response_metadata(%{}, response, []) == %{}

      response = Req.Response.new(status: 400, body: "Bad Request")

      assert provider.response_metadata(%{feature: :summarizer}, response, []) == %{
               feature: :summarizer
             }
    end)
  end

  test "built-in providers extract non-streaming usage when available" do
    providers = [
      {ReqAI.Provider.Anthropic, "input_tokens", "output_tokens"},
      {ReqAI.Provider.OpenAI, "input_tokens", "output_tokens"},
      {ReqAI.Provider.XAI, "input_tokens", "output_tokens"},
      {ReqAI.Provider.Gemini, "total_input_tokens", "total_output_tokens"},
      {ReqAI.Provider.OpenRouter, "prompt_tokens", "completion_tokens"}
    ]

    for {provider, input_key, output_key} <- providers,
        {usage, expected} <- [
          {%{input_key => 12, output_key => 8}, %{input_tokens: 12, output_tokens: 8}},
          {%{input_key => 0}, %{input_tokens: 0}},
          {%{output_key => 0}, %{output_tokens: 0}},
          {%{input_key => nil, output_key => nil}, %{}},
          {%{}, %{}},
          {nil, %{}}
        ] do
      body = %{"model" => "response-model", "usage" => usage}
      response = Req.Response.new(status: 200, body: body)
      metadata = %{feature: :summarizer}

      assert provider.response_metadata(metadata, response, stream: false) ==
               Map.merge(expected, %{feature: :summarizer, response_model: "response-model"})
    end
  end

  test "finish reasons use each provider's API fields in responses and stream events" do
    cases = [
      {ReqAI.Provider.Anthropic, %{"stop_reason" => "end_turn"}, "end_turn"},
      {ReqAI.Provider.OpenAI,
       %{"status" => "incomplete", "incomplete_details" => %{"reason" => "max_output_tokens"}},
       "max_output_tokens"},
      {ReqAI.Provider.XAI, %{"status" => "completed"}, "completed"},
      {ReqAI.Provider.Gemini, %{"status" => "completed"}, "completed"},
      {ReqAI.Provider.OpenRouter,
       %{"choices" => [%{"finish_reason" => "stop", "native_finish_reason" => "end_turn"}]},
       "stop"}
    ]

    for {provider, body, reason} <- cases do
      response = Req.Response.new(status: 200, body: body)
      metadata = %{feature: :summarizer}
      result = provider.response_metadata(metadata, response, [])
      assert result.finish_reasons == [reason]
      refute Map.has_key?(result, :finish_reason)
      assert result.feature == :summarizer

      result = provider.event_metadata(metadata, finish_event(provider, body), response, [])
      assert result.finish_reasons == [reason]
      refute Map.has_key?(result, :finish_reason)
      assert result.feature == :summarizer

      # A later event without a reason must preserve the accumulated value.
      assert provider.event_metadata(result, finish_event(provider, %{}), response, []) == result
    end
  end

  test "OpenRouter preserves all choice finish reasons in responses and streams" do
    body = %{
      "choices" => [
        %{"finish_reason" => "stop"},
        %{"finish_reason" => nil},
        %{"finish_reason" => "length"},
        %{"finish_reason" => "stop"}
      ]
    }

    response = Req.Response.new(status: 200, body: body)
    expected = %{finish_reasons: ["stop", "length", "stop"]}
    assert ReqAI.Provider.OpenRouter.response_metadata(%{}, response, []) == expected
    assert ReqAI.Provider.OpenRouter.event_metadata(%{}, %{data: body}, response, []) == expected
  end

  test "missing, null, and nonterminal fields do not introduce finish reasons" do
    cases = [
      {ReqAI.Provider.Anthropic, %{"stop_reason" => nil}},
      {ReqAI.Provider.OpenAI, %{"status" => nil}},
      {ReqAI.Provider.OpenAI, %{"status" => "queued"}},
      {ReqAI.Provider.OpenAI, %{"status" => "in_progress"}},
      {ReqAI.Provider.XAI, %{"status" => "in_progress"}},
      {ReqAI.Provider.Gemini, %{"status" => "in_progress"}},
      {ReqAI.Provider.OpenRouter, %{"choices" => []}},
      {ReqAI.Provider.OpenRouter, %{"choices" => nil}},
      {ReqAI.Provider.OpenRouter, %{"choices" => [%{"finish_reason" => nil}]}}
    ]

    for {provider, body} <- cases, metadata <- [%{}, %{finish_reasons: ["previous"]}] do
      response = Req.Response.new(status: 200, body: body)
      assert provider.response_metadata(metadata, response, []) == metadata

      assert provider.event_metadata(metadata, finish_event(provider, body), response, []) ==
               metadata
    end
  end

  test "Gemini status updates report terminal statuses and preserve them on later events" do
    response = Req.Response.new(status: 200)

    for status <- ["completed", "requires_action", "failed", "cancelled", "incomplete"] do
      event = %{data: %{"event_type" => "interaction.status_update", "status" => status}}
      metadata = ReqAI.Provider.Gemini.event_metadata(%{}, event, response, [])
      assert metadata == %{finish_reasons: [status]}

      event = %{data: %{"event_type" => "interaction.status_update", "status" => "in_progress"}}
      assert ReqAI.Provider.Gemini.event_metadata(metadata, event, response, []) == metadata
    end
  end

  defp finish_event(ReqAI.Provider.Anthropic, body),
    do: %{data: %{"type" => "message_delta", "delta" => body}}

  defp finish_event(ReqAI.Provider.Gemini, body), do: %{data: %{"interaction" => body}}
  defp finish_event(ReqAI.Provider.OpenRouter, body), do: %{data: body}
  defp finish_event(_provider, body), do: %{data: %{"response" => body}}

  test "built-in providers fold telemetry from decoded stream events" do
    response = Req.Response.new(status: 200)

    anthropic_metadata =
      ReqAI.Provider.Anthropic.event_metadata(
        %{feature: :summarizer},
        %{
          data: %{
            "type" => "message_start",
            "message" => %{
              "model" => "claude-sonnet-4-5",
              "usage" => %{"input_tokens" => 25, "output_tokens" => 1}
            }
          }
        },
        response,
        []
      )

    assert ReqAI.Provider.Anthropic.event_metadata(
             anthropic_metadata,
             %{
               data: %{
                 "type" => "message_delta",
                 "delta" => %{"stop_reason" => "end_turn"},
                 "usage" => %{"output_tokens" => 15}
               }
             },
             response,
             []
           ) == %{
             finish_reasons: ["end_turn"],
             response_model: "claude-sonnet-4-5",
             input_tokens: 25,
             output_tokens: 15,
             feature: :summarizer
           }

    responses_event = %{
      data: %{
        "type" => "response.completed",
        "response" => %{
          "model" => "response-model",
          "usage" => %{"input_tokens" => 12, "output_tokens" => 8}
        }
      }
    }

    for provider <- [ReqAI.Provider.OpenAI, ReqAI.Provider.XAI] do
      assert provider.event_metadata(%{}, responses_event, response, []) == %{
               response_model: "response-model",
               input_tokens: 12,
               output_tokens: 8
             }
    end

    gemini_event = %{
      data: %{
        "event_type" => "interaction.completed",
        "interaction" => %{
          "model" => "gemini-3-pro",
          "usage" => %{"total_input_tokens" => 19, "total_output_tokens" => 7}
        }
      }
    }

    assert ReqAI.Provider.Gemini.event_metadata(%{}, gemini_event, response, []) == %{
             response_model: "gemini-3-pro",
             input_tokens: 19,
             output_tokens: 7
           }

    open_router_event = %{
      data: %{
        "model" => "openai/gpt-5",
        "choices" => [%{"finish_reason" => "stop"}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 4}
      }
    }

    assert ReqAI.Provider.OpenRouter.event_metadata(
             %{},
             open_router_event,
             response,
             []
           ) == %{
             finish_reasons: ["stop"],
             response_model: "openai/gpt-5",
             input_tokens: 10,
             output_tokens: 4
           }
  end

  test "built-in providers do not add nil attributes from stream events" do
    response = Req.Response.new(status: 200)

    for provider <- [
          ReqAI.Provider.Anthropic,
          ReqAI.Provider.Gemini,
          ReqAI.Provider.OpenAI,
          ReqAI.Provider.OpenRouter,
          ReqAI.Provider.XAI
        ] do
      assert provider.event_metadata(%{}, %{data: %{}}, response, []) == %{}
      assert provider.event_metadata(%{}, :unknown, response, []) == %{}
    end
  end

  test "built-in providers decode JSON SSE events and discard protocol events" do
    providers = [
      ReqAI.Provider.Anthropic,
      ReqAI.Provider.Gemini,
      ReqAI.Provider.OpenAI,
      ReqAI.Provider.OpenRouter,
      ReqAI.Provider.XAI
    ]

    response = Req.Response.new(status: 200)
    event = %{event: "response.output_text.delta", data: ~s({"delta":"Hello!"})}
    decoded_event = %{event | data: %{"delta" => "Hello!"}}

    Enum.each(providers, fn provider ->
      assert provider.decode_event(event, response, stream: true) == [decoded_event]
      assert provider.decode_event(%{event: "ping", data: "not-json"}, response, []) == []
      assert provider.decode_event(%{data: "[DONE]"}, response, []) == []
      assert provider.decode_event(%{data: ""}, response, []) == []
      assert provider.decode_event(:unknown, response, []) == []

      assert_raise RuntimeError, ~s(non-JSON SSE data "not-json"), fn ->
        provider.decode_event(%{data: "not-json"}, response, [])
      end
    end)
  end
end
