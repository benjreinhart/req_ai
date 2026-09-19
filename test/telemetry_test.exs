defmodule ReqAI.TelemetryTest do
  use ExUnit.Case, async: true

  alias ReqAI.{Provider, Telemetry}

  @openai_response %Req.Response{
    body: %{
      "model" => "gpt-5.6-sol-v123",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 20}
    }
  }

  @openai_error_response %Req.Response{
    status: 400,
    body: %{"error" => "Bad Request"}
  }

  defmodule CustomTelemetry do
    # No callbacks defined
  end

  defmodule EventTelemetry do
    @behaviour Telemetry

    @impl true
    def event_metadata(metadata, event, response, opts) do
      Map.put(metadata, :event, {event, response, opts})
    end
  end

  @events [
    [:event, :prefix, :start],
    [:event, :prefix, :stop],
    [:event, :prefix, :exception]
  ]

  describe "Telemetry.span/5" do
    test "does not emit when provider telemetry is disabled" do
      ref = :telemetry_test.attach_event_handlers(self(), @events)

      provider = Provider.new(ReqAI.Provider.OpenAI, telemetry: false)

      Telemetry.span(
        provider.telemetry,
        provider.telemetry_metadata,
        [:event, :prefix],
        %{model: "gpt-5.6-sol"},
        [stream: false],
        fn metadata ->
          {{:ok, :result}, %{}, {:response, @openai_response, metadata}}
        end
      )

      refute_receive {[:event, :prefix, :start], ^ref, _, _}
      refute_receive {[:event, :prefix, :stop], ^ref, _, _}
      refute_receive {[:event, :prefix, :exception], ^ref, _, _}
    end

    test "ignores optional callbacks not provided" do
      ref = :telemetry_test.attach_event_handlers(self(), @events)

      provider = Provider.new(ReqAI.Provider.OpenAI, telemetry: CustomTelemetry)

      Telemetry.span(
        provider.telemetry,
        provider.telemetry_metadata,
        [:event, :prefix],
        %{model: "gpt-5.6-sol"},
        [stream: false],
        fn metadata ->
          {{:ok, :result}, %{}, {:ok, @openai_response, metadata}}
        end
      )

      assert_receive {[:event, :prefix, :start], ^ref, %{}, %{} = start_meta}
      assert_receive {[:event, :prefix, :stop], ^ref, %{}, %{} = stop_meta}
      refute_receive {[:event, :prefix, :exception], ^ref, _, _}

      start_meta = Map.delete(start_meta, :telemetry_span_context)
      stop_meta = Map.delete(stop_meta, :telemetry_span_context)

      assert start_meta == %{}
      assert stop_meta == %{}
    end

    test "emits start and stop when successful" do
      ref = :telemetry_test.attach_event_handlers(self(), @events)

      provider = Provider.new(ReqAI.Provider.OpenAI, [])

      Telemetry.span(
        provider.telemetry,
        provider.telemetry_metadata,
        [:event, :prefix],
        %{model: "gpt-5.6-sol"},
        [stream: false],
        fn metadata ->
          metadata = Map.put(metadata, :added_key, "added value")
          {{:ok, :result}, %{}, {:ok, @openai_response, metadata}}
        end
      )

      assert_receive {[:event, :prefix, :start], ^ref, %{system_time: t}, %{} = start_meta}
      assert_receive {[:event, :prefix, :stop], ^ref, %{duration: d}, %{} = stop_meta}
      refute_receive {[:event, :prefix, :exception], ^ref, _, _}

      {start_span_ctx, start_meta} = Map.pop(start_meta, :telemetry_span_context)
      {stop_span_ctx, stop_meta} = Map.pop(stop_meta, :telemetry_span_context)

      assert is_integer(t)
      assert is_integer(d) and d > 0
      assert start_span_ctx == stop_span_ctx

      expected_start_meta = %{
        model: "gpt-5.6-sol",
        operation: "chat",
        provider: "openai"
      }

      expected_stop_meta =
        Map.merge(expected_start_meta, %{
          added_key: "added value",
          response_model: "gpt-5.6-sol-v123",
          input_tokens: 10,
          output_tokens: 20
        })

      assert start_meta == expected_start_meta
      assert stop_meta == expected_stop_meta
    end

    test "emits start and stop when unsuccessful" do
      ref = :telemetry_test.attach_event_handlers(self(), @events)

      provider = Provider.new(ReqAI.Provider.OpenAI, [])

      Telemetry.span(
        provider.telemetry,
        provider.telemetry_metadata,
        [:event, :prefix],
        %{model: "gpt-5.6-sol"},
        [stream: false],
        fn metadata ->
          metadata = Map.put(metadata, :added_key, "added value")
          {{:ok, :result}, %{}, {:ok, @openai_error_response, metadata}}
        end
      )

      assert_receive {[:event, :prefix, :start], ^ref, %{system_time: t}, %{} = start_meta}
      assert_receive {[:event, :prefix, :stop], ^ref, %{duration: d}, %{} = stop_meta}
      refute_receive {[:event, :prefix, :exception], ^ref, _, _}

      {start_span_ctx, start_meta} = Map.pop(start_meta, :telemetry_span_context)
      {stop_span_ctx, stop_meta} = Map.pop(stop_meta, :telemetry_span_context)

      assert is_integer(t)
      assert is_integer(d) and d > 0
      assert start_span_ctx == stop_span_ctx

      expected_start_meta = %{
        model: "gpt-5.6-sol",
        operation: "chat",
        provider: "openai"
      }

      expected_stop_meta =
        Map.merge(expected_start_meta, %{
          added_key: "added value"
        })

      assert start_meta == expected_start_meta
      assert stop_meta == expected_stop_meta
    end

    test "emits start and stop when exceptional" do
      ref = :telemetry_test.attach_event_handlers(self(), @events)

      provider = Provider.new(ReqAI.Provider.OpenAI, [])

      Telemetry.span(
        provider.telemetry,
        provider.telemetry_metadata,
        [:event, :prefix],
        %{model: "gpt-5.6-sol"},
        [stream: false],
        fn metadata ->
          metadata = Map.put(metadata, :added_key, "added value")
          {{:ok, :result}, %{}, {:error, %Req.TransportError{reason: :timeout}, metadata}}
        end
      )

      assert_receive {[:event, :prefix, :start], ^ref, %{system_time: t}, %{} = start_meta}
      assert_receive {[:event, :prefix, :stop], ^ref, %{duration: d}, %{} = stop_meta}
      refute_receive {[:event, :prefix, :exception], ^ref, _, _}

      {start_span_ctx, start_meta} = Map.pop(start_meta, :telemetry_span_context)
      {stop_span_ctx, stop_meta} = Map.pop(stop_meta, :telemetry_span_context)

      assert is_integer(t)
      assert is_integer(d) and d > 0
      assert start_span_ctx == stop_span_ctx

      expected_start_meta = %{
        model: "gpt-5.6-sol",
        operation: "chat",
        provider: "openai"
      }

      expected_stop_meta =
        Map.merge(expected_start_meta, %{
          added_key: "added value"
        })

      assert start_meta == expected_start_meta
      assert stop_meta == expected_stop_meta
    end
  end

  describe "Telemetry.event_metadata/5" do
    test "preserves metadata when telemetry is disabled" do
      metadata = %{request_id: "request-123"}

      assert Telemetry.event_metadata(false, metadata, %{}, @openai_response, stream: true) ==
               metadata

      assert Telemetry.event_metadata(false, nil, %{}, @openai_response, stream: true) == nil
    end

    test "preserves metadata when the optional callback is not provided" do
      metadata = %{request_id: "request-123"}

      assert Telemetry.event_metadata(
               CustomTelemetry,
               metadata,
               %{},
               @openai_response,
               stream: true
             ) == metadata
    end

    test "passes metadata, event, response and options to the callback and returns its result" do
      metadata = %{request_id: "request-123"}
      event = %{event: "response.output_text.delta", data: %{"delta" => "some chunk "}}
      opts = [stream: true, custom_option: :value]

      assert Telemetry.event_metadata(EventTelemetry, metadata, event, @openai_response, opts) ==
               %{
                 request_id: "request-123",
                 event: {event, @openai_response, opts}
               }
    end
  end
end
