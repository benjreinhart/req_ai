defmodule ReqAITest do
  use ExUnit.Case, async: true

  alias ReqAI.Provider.OpenAI
  alias ReqAITest.ReqStubs

  defmodule UnifiedRequest do
    defstruct [:model, :prompt, provider_options: %{}]
  end

  defmodule RequestTranslator do
    @behaviour ReqAI.Translator

    @impl true
    def request(%ReqAITest.UnifiedRequest{} = request, opts) do
      send(self(), {:translate_request, opts[:stream], opts[:request_context]})

      %{model: request.model, input: request.prompt}
      |> Map.merge(Map.get(request.provider_options, :openai, %{}))
    end
  end

  defmodule ResponseTranslator do
    @behaviour ReqAI.Translator

    @impl true
    def response(response, opts), do: {:response, response.status, response.body, opts[:stream]}

    @impl true
    def error(response, opts), do: {:error, response.status, response.body, opts[:stream]}

    @impl true
    def event(event, response, opts), do: {:event, event, response.status, opts[:stream]}
  end

  defmodule RaisingResponseTranslator do
    @behaviour ReqAI.Translator

    @impl true
    def response(_response, _opts), do: raise("response translation failed")
  end

  defmodule ProviderWithoutTelemetry do
    @behaviour ReqAI.Provider

    @impl true
    def build(req, request, opts), do: ReqAI.Provider.OpenAI.build(req, request, opts)

    @impl true
    def decode_event(event, _response, _opts), do: [event]
  end

  defmodule ExpandingProvider do
    @behaviour ReqAI.Provider

    @impl true
    def build(req, request, opts), do: ReqAI.Provider.OpenAI.build(req, request, opts)

    @impl true
    def decode_event(event, _response, _opts), do: [{:first, event}, {:second, event}]
  end

  defmodule CustomTelemetry do
    @behaviour ReqAI.Telemetry

    @impl true
    def request_metadata(metadata, request, opts) do
      send(self(), {:extract_request_telemetry, metadata, request, opts[:stream]})
      Map.put(metadata, :custom_request, Map.fetch!(request, :model))
    end

    @impl true
    def response_metadata(metadata, response, opts) do
      send(self(), {:extract_response_telemetry, metadata, response.body, opts[:stream]})
      Map.put(metadata, :custom_response, response.body["model"])
    end

    @impl true
    def event_metadata(metadata, event, response, opts) do
      send(self(), {:extract_event_telemetry, metadata, event, response.status, opts[:stream]})
      Map.put(metadata, :custom_event, event.data["type"])
    end
  end

  defmodule MinimalTelemetry do
    @behaviour ReqAI.Telemetry

    @impl true
    def request_metadata(metadata, _request, _opts), do: Map.put(metadata, :request_only, true)
  end

  @request %{model: "gpt-5.4", input: "Say hello."}

  describe "stream/4" do
    test "emits telemetry and folds every decoded event into the stop metadata" do
      attach_stream_telemetry()

      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          body: [
            {:data,
             ~s(event: response.created\ndata: {"type":"response.created","response":{"model":"gpt-5.4-2026-08-01","usage":null}}\n\n)},
            {:data,
             ~s(event: response.completed\ndata: {"type":"response.completed","response":{"model":"gpt-5.4-2026-08-01","usage":{"input_tokens":11,"output_tokens":4}}}\n\n)}
          ]
        )

      assert {:ok, %Req.Response{status: 200}, 2} =
               ReqAI.stream(provider, @request, 0, fn _event, _response, count ->
                 {:cont, count + 1}
               end)

      assert_receive {:telemetry, [:req_ai, :stream, :start], _measurements,
                      %{
                        stream: true,
                        model: "gpt-5.4",
                        provider: "openai"
                      }}

      assert_receive {:telemetry, [:req_ai, :stream, :stop],
                      %{
                        duration: duration,
                        time_to_first_chunk: time_to_first_chunk
                      },
                      %{
                        status_code: 200,
                        stream: true,
                        response_model: "gpt-5.4-2026-08-01",
                        input_tokens: 11,
                        output_tokens: 4,
                        error: false
                      }}

      assert duration >= 0
      assert time_to_first_chunk >= 0
      assert time_to_first_chunk <= duration
    end

    test "does not record time to first chunk when the response stream is empty" do
      attach_stream_telemetry()

      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          body: []
        )

      assert {:ok, %Req.Response{status: 200}, :initial} =
               ReqAI.stream(provider, @request, :initial, fn _event, _response, _acc ->
                 flunk("callback should not be invoked for an empty stream")
               end)

      assert_receive {:telemetry, [:req_ai, :stream, :stop], measurements, %{error: false}}

      assert %{duration: duration} = measurements
      refute Map.has_key?(measurements, :time_to_first_chunk)
      assert duration >= 0
    end

    test "records time to first chunk for a protocol-only stream event" do
      attach_stream_telemetry()

      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          body: [{:data, ~s(event: ping\ndata: not-json\n\n)}]
        )

      assert {:ok, %Req.Response{status: 200}, :initial} =
               ReqAI.stream(provider, @request, :initial, fn _event, _response, _acc ->
                 flunk("callback should not be invoked for a protocol-only event")
               end)

      assert_receive {:telemetry, [:req_ai, :stream, :stop],
                      %{
                        duration: duration,
                        time_to_first_chunk: time_to_first_chunk
                      }, %{error: false}}

      assert time_to_first_chunk >= 0
      assert time_to_first_chunk <= duration
    end

    test "uses the configured telemetry event callback with decoded provider events" do
      attach_stream_telemetry()

      provider =
        ReqStubs.stub_provider_response_stream(
          {OpenAI, [telemetry: CustomTelemetry, telemetry_metadata: %{feature: :summarizer}]},
          body: [
            {:data,
             ~s(event: response.completed\ndata: {"type":"response.completed","response":{"model":"gpt-5.4-2026-08-01"}}\n\n)}
          ]
        )

      assert {:ok, _response, :initial} =
               ReqAI.stream(provider, @request, :initial, fn event, _response, acc ->
                 assert event.data["type"] == "response.completed"
                 {:cont, acc}
               end)

      assert_receive {:extract_event_telemetry,
                      %{
                        custom_request: "gpt-5.4",
                        feature: :summarizer,
                        stream: true
                      }, %{data: %{"type" => "response.completed"}}, 200, true}

      assert_receive {:telemetry, [:req_ai, :stream, :stop], _measurements,
                      %{
                        custom_event: "response.completed",
                        custom_request: "gpt-5.4",
                        feature: :summarizer
                      }}

      refute_receive {:extract_response_telemetry, _, _, true}
    end

    test "translates application input with streaming enabled before building the request" do
      provider =
        ReqStubs.stub_provider_response_stream(
          {ProviderWithoutTelemetry, [translator: RequestTranslator, request_context: :test]},
          headers: [{"content-type", "application/octet-stream"}],
          body: [{:data, "Hello!"}]
        )

      request = %UnifiedRequest{model: "gpt-5.4", prompt: "Say hello."}

      assert {:ok, _response, ["Hello!"]} =
               ReqAI.stream(provider, request, [], fn chunk, _response, chunks ->
                 {:cont, chunks ++ [chunk]}
               end)

      assert_receive {:translate_request, true, :test}
      assert_receive {:request, request}

      assert request.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "input" => "Say hello.",
               "model" => "gpt-5.4",
               "stream" => true
             }
    end

    test "builds a streaming request and emits decoded SSE events" do
      provider =
        ReqStubs.stub_provider_response_stream(
          {OpenAI, [stream: false]},
          body: [
            {:data,
             ~s(event: response.output_text.delta\ndata: {"type":"response.output_text.delta",)},
            {:data, ~s("delta":"Hello!"}\n\n)},
            {:data,
             ~s(event: response.completed\ndata: {"type":"response.completed","response":{"id":"resp_123","status":"completed"}}\n\n)},
            {:data, ~s(event: ping\ndata: not-json\n\n)},
            {:data, ~s(data: [DONE]\n\n)}
          ]
        )

      assert {:ok, response, events} =
               ReqAI.stream(provider, Map.put(@request, :stream, false), [], fn
                 event, response, events ->
                   assert response.status == 200
                   {:cont, events ++ [event]}
               end)

      assert response.status == 200
      assert Req.Response.get_header(response, "content-type") == ["text/event-stream"]

      assert Enum.map(events, & &1.data) == [
               %{"type" => "response.output_text.delta", "delta" => "Hello!"},
               %{
                 "type" => "response.completed",
                 "response" => %{"id" => "resp_123", "status" => "completed"}
               }
             ]

      assert_receive {:request, request}

      assert request.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "input" => "Say hello.",
               "model" => "gpt-5.4",
               "stream" => true
             }
    end

    test "stream allows the callback to halt consumption" do
      provider =
        ReqStubs.stub_provider_response_stream(ProviderWithoutTelemetry,
          headers: [{"content-type", "application/octet-stream"}],
          body: [{:data, "first"}, {:data, "second"}]
        )

      assert {:ok, response, ["first"]} =
               ReqAI.stream(provider, @request, [], fn chunk, _response, chunks ->
                 {:halt, [chunk | chunks]}
               end)

      assert response.status == 200
    end

    test "translates streamed events and preserves the completed HTTP response" do
      provider =
        ReqStubs.stub_provider_response_stream(
          {ProviderWithoutTelemetry, [translator: ResponseTranslator]},
          headers: [{"content-type", "application/octet-stream"}],
          body: [{:data, "Hello!"}]
        )

      assert {:ok, %Req.Response{status: 200}, [{:event, "Hello!", 200, true}]} =
               ReqAI.stream(provider, @request, [], fn event, response, events ->
                 assert %Req.Response{status: 200} = response
                 {:cont, [event | events]}
               end)
    end

    test "passes every event returned by the provider decoder to the callback" do
      provider =
        ReqStubs.stub_provider_response_stream(ExpandingProvider,
          headers: [{"content-type", "application/octet-stream"}],
          body: [{:data, "Hello!"}]
        )

      assert {:ok, %Req.Response{status: 200}, [first: "Hello!", second: "Hello!"]} =
               ReqAI.stream(provider, @request, [], fn event, _response, events ->
                 {:cont, events ++ [event]}
               end)
    end

    test "stream buffers JSON error responses without invoking the callback" do
      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          status: 401,
          headers: [{"content-type", "application/json"}],
          body: [
            {:data, ~s({"error":{"message":)},
            {:data, ~s("Invalid API key.","type":"invalid_request_error"}})}
          ]
        )

      assert {:error, response, error} =
               ReqAI.stream(provider, @request, :initial, fn _chunk, _response, _acc ->
                 flunk("callback should not be invoked for a non-2xx response")
               end)

      assert response.status == 401

      assert error == response.body

      assert error == %{
               "error" => %{
                 "message" => "Invalid API key.",
                 "type" => "invalid_request_error"
               }
             }
    end

    test "translates a buffered non-successful streaming response" do
      provider =
        ReqStubs.stub_provider_response_stream(
          {OpenAI, [translator: ResponseTranslator]},
          status: 400,
          headers: [{"content-type", "application/json"}],
          body: [{:data, ~s({"error":"Invalid request."})}]
        )

      assert {:error, %Req.Response{status: 400} = response,
              {:error, 400, %{"error" => "Invalid request."}, true}} =
               ReqAI.stream(provider, @request, :initial, fn _event, _response, _acc ->
                 flunk("callback should not be invoked for a non-2xx response")
               end)

      assert response.body == %{"error" => "Invalid request."}
    end

    test "stream buffers plain-text error responses" do
      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          status: 429,
          headers: [{"content-type", "text/plain"}],
          body: [{:data, "rate "}, {:data, "limited"}]
        )

      assert {:error, response, "rate limited"} =
               ReqAI.stream(provider, @request, [], fn _chunk, _response, _acc ->
                 flunk("callback should not be invoked for a non-2xx response")
               end)

      assert response.status == 429
      assert response.body == "rate limited"
    end

    test "preserves transport errors and the accumulator" do
      exception = %Req.TransportError{reason: :timeout}
      provider = ReqStubs.stub_provider_response_exception(OpenAI, exception)

      assert {:error, ^exception, response, :initial} =
               ReqAI.stream(provider, @request, :initial, fn _chunk, _response, acc ->
                 {:cont, acc}
               end)

      assert response.status == nil
    end
  end

  describe "generate/2" do
    test "emits telemetry for a successful response" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(OpenAI,
          body: %{"model" => "gpt-5.4-2026-08-01", "status" => "completed"}
        )

      assert {:ok, _response, _result} = ReqAI.generate(provider, @request)

      assert_receive {:telemetry, [:req_ai, :generate, :start],
                      %{monotonic_time: monotonic_time, system_time: system_time},
                      %{
                        operation: "chat",
                        provider: "openai",
                        model: "gpt-5.4"
                      }}

      assert is_integer(monotonic_time)
      assert is_integer(system_time)

      assert_receive {:telemetry, [:req_ai, :generate, :stop],
                      %{duration: duration, monotonic_time: monotonic_time},
                      %{
                        status_code: 200,
                        operation: "chat",
                        provider: "openai",
                        model: "gpt-5.4",
                        response_model: "gpt-5.4-2026-08-01",
                        error: false
                      }}

      assert is_integer(duration)
      assert duration >= 0
      assert is_integer(monotonic_time)
    end

    test "uses an overridden extractor and merges static metadata into every event" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [telemetry: CustomTelemetry, telemetry_metadata: %{feature: :summarizer}]},
          body: %{"model" => "gpt-5.4-2026-08-01", "status" => "completed"}
        )

      assert {:ok, _response, _result} = ReqAI.generate(provider, @request)

      assert_receive {:extract_request_telemetry, %{feature: :summarizer}, @request, false}

      assert_receive {:telemetry, [:req_ai, :generate, :start], _measurements,
                      %{custom_request: "gpt-5.4", feature: :summarizer} = metadata}

      refute Map.has_key?(metadata, :provider)

      assert_receive {:extract_response_telemetry,
                      %{
                        custom_request: "gpt-5.4",
                        feature: :summarizer,
                        status_code: 200,
                        error: false
                      }, %{"model" => "gpt-5.4-2026-08-01", "status" => "completed"}, false}

      assert_receive {:telemetry, [:req_ai, :generate, :stop], _measurements,
                      %{
                        custom_request: "gpt-5.4",
                        custom_response: "gpt-5.4-2026-08-01",
                        feature: :summarizer
                      }}
    end

    test "supports an extractor without a response callback" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [telemetry: MinimalTelemetry]},
          body: %{"status" => "completed"}
        )

      assert {:ok, _response, _result} = ReqAI.generate(provider, @request)

      assert_receive {:telemetry, [:req_ai, :generate, :stop], _measurements,
                      %{
                        request_only: true,
                        status_code: 200,
                        error: false
                      }}
    end

    test "supports a provider without telemetry callbacks" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(
          {ProviderWithoutTelemetry, [telemetry_metadata: %{feature: :summarizer}]},
          body: %{"status" => "completed"}
        )

      assert {:ok, _response, _result} = ReqAI.generate(provider, @request)

      assert_receive {:telemetry, [:req_ai, :generate, :start], _measurements,
                      %{feature: :summarizer}}

      assert_receive {:telemetry, [:req_ai, :generate, :stop], _measurements,
                      %{
                        status_code: 200,
                        error: false,
                        feature: :summarizer
                      }}
    end

    test "disables extraction and emission when telemetry is false" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [telemetry: false, telemetry_metadata: %{feature: :summarizer}]},
          body: %{"status" => "completed"}
        )

      assert {:ok, _response, _result} = ReqAI.generate(provider, @request)
      refute_receive {:telemetry, [:req_ai, :generate, _lifecycle], _, _}
    end

    test "emits error telemetry for a non-successful HTTP response" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(OpenAI,
          status: 429,
          body: %{"error" => %{"message" => "Rate limited."}}
        )

      assert {:error, _response, _error} = ReqAI.generate(provider, @request)

      assert_receive {:telemetry, [:req_ai, :generate, :stop], %{duration: duration},
                      %{
                        error_type: "429",
                        status_code: 429,
                        provider: "openai",
                        model: "gpt-5.4",
                        error: true
                      }}

      assert duration >= 0
    end

    test "emits error telemetry for a transport error" do
      attach_generate_telemetry()

      exception = %Req.TransportError{reason: :timeout}

      provider =
        ReqStubs.stub_provider_response_exception(
          {OpenAI, [telemetry: CustomTelemetry, telemetry_metadata: %{feature: :summarizer}]},
          exception
        )

      assert {:error, ^exception} = ReqAI.generate(provider, @request)

      assert_receive {:telemetry, [:req_ai, :generate, :stop], %{duration: duration},
                      %{
                        custom_request: "gpt-5.4",
                        error_type: "timeout",
                        feature: :summarizer,
                        error: true
                      } = metadata}

      refute Map.has_key?(metadata, :response_model)
      refute Map.has_key?(metadata, :status_code)
      assert duration >= 0
    end

    test "emits standard exception telemetry and reraises" do
      attach_generate_telemetry()

      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI,
           [
             translator: RaisingResponseTranslator,
             telemetry_metadata: %{feature: :summarizer}
           ]},
          body: %{"model" => "gpt-5.4-2026-08-01", "status" => "completed"}
        )

      assert_raise RuntimeError, "response translation failed", fn ->
        ReqAI.generate(provider, @request)
      end

      assert_receive {:telemetry, [:req_ai, :generate, :exception],
                      %{duration: duration, monotonic_time: monotonic_time},
                      %{
                        provider: "openai",
                        model: "gpt-5.4",
                        feature: :summarizer,
                        kind: :error,
                        reason: %RuntimeError{message: "response translation failed"},
                        stacktrace: stacktrace
                      }}

      assert duration >= 0
      assert is_integer(monotonic_time)
      assert is_list(stacktrace)
    end

    test "translates application input with streaming disabled before building the request" do
      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [translator: RequestTranslator, request_context: :test]},
          body: %{"status" => "completed"}
        )

      request = %UnifiedRequest{
        model: "gpt-5.4",
        prompt: "Say hello.",
        provider_options: %{openai: %{temperature: 0.5}}
      }

      assert {:ok, _response, _result} = ReqAI.generate(provider, request)
      assert_receive {:translate_request, false, :test}
      assert_receive {:request, request}

      assert request.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "input" => "Say hello.",
               "model" => "gpt-5.4",
               "stream" => false,
               "temperature" => 0.5
             }
    end

    test "returns a successful response" do
      response_body = %{
        "id" => "resp_123",
        "object" => "response",
        "status" => "completed",
        "model" => "gpt-5.4",
        "output" => []
      }

      provider =
        ReqStubs.stub_provider_response_json(OpenAI, body: response_body)

      assert {:ok, response, result} =
               ReqAI.generate(provider, Map.put(@request, :stream, true))

      assert response.status == 200
      assert response.body == response_body
      assert result == response_body

      assert_receive {:request, request}

      assert request.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "input" => "Say hello.",
               "model" => "gpt-5.4",
               "stream" => false
             }
    end

    test "translates a completed response" do
      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [translator: ResponseTranslator]},
          body: %{"status" => "completed"}
        )

      assert {:ok, %Req.Response{status: 200} = response,
              {:response, 200, %{"status" => "completed"}, false}} =
               ReqAI.generate(provider, @request)

      assert response.body == %{"status" => "completed"}
    end

    test "returns a non-successful response as an error" do
      error_body = %{
        "error" => %{
          "message" => "Invalid request.",
          "type" => "invalid_request_error"
        }
      }

      provider =
        ReqStubs.stub_provider_response_json(OpenAI,
          status: 400,
          body: error_body
        )

      assert {:error, response, error} = ReqAI.generate(provider, @request)
      assert response.status == 400
      assert response.body == error_body
      assert error == error_body
    end

    test "translates a non-successful response after classifying it as an error" do
      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [translator: ResponseTranslator]},
          status: 400,
          body: %{"error" => "Invalid request."}
        )

      assert {:error, %Req.Response{status: 400} = response,
              {:error, 400, %{"error" => "Invalid request."}, false}} =
               ReqAI.generate(provider, @request)

      assert response.body == %{"error" => "Invalid request."}
    end

    test "does not translate a non-successful response with response/2" do
      provider =
        ReqStubs.stub_provider_response_json(
          {OpenAI, [translator: RaisingResponseTranslator]},
          status: 400,
          body: %{"error" => "Invalid request."}
        )

      assert {:error, %Req.Response{status: 400}, %{"error" => "Invalid request."}} =
               ReqAI.generate(provider, @request)
    end

    test "returns request exceptions" do
      exception = %Req.TransportError{reason: :timeout}

      provider = ReqStubs.stub_provider_response_exception(OpenAI, exception)

      assert {:error, ^exception} = ReqAI.generate(provider, @request)
    end
  end

  test "telemetry span forwards additional stop measurements" do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}
    event_prefix = [:req_ai, :test_span]

    :ok =
      :telemetry.attach(
        handler_id,
        event_prefix ++ [:stop],
        &__MODULE__.handle_telemetry_event/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    provider = ReqAI.Provider.new(ProviderWithoutTelemetry, [])
    response = Req.Response.new(status: 200)

    assert :result =
             ReqAI.Telemetry.span(provider, event_prefix, %{}, [], fn metadata ->
               {:result, %{custom_measurement: 42}, {:stream, response, false, metadata}}
             end)

    assert_receive {:telemetry, [:req_ai, :test_span, :stop],
                    %{
                      custom_measurement: 42,
                      duration: duration,
                      monotonic_time: monotonic_time
                    }, %{status_code: 200, error: false}}

    assert duration >= 0
    assert is_integer(monotonic_time)
  end

  defp attach_generate_telemetry do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:req_ai, :generate, :start],
          [:req_ai, :generate, :stop],
          [:req_ai, :generate, :exception]
        ],
        &__MODULE__.handle_telemetry_event/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp attach_stream_telemetry do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:req_ai, :stream, :start],
          [:req_ai, :stream, :stop],
          [:req_ai, :stream, :exception]
        ],
        &__MODULE__.handle_telemetry_event/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  @doc false
  def handle_telemetry_event(event, measurements, metadata, pid) do
    if self() == pid do
      send(pid, {:telemetry, event, measurements, metadata})
    end
  end
end
