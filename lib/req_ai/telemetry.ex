defmodule ReqAI.Telemetry do
  @moduledoc """
  Attribute extraction callbacks for telemetry events.

  `ReqAI.generate/2` emits `[:req_ai, :generate, :start]`,
  `[:req_ai, :generate, :stop]`, and `[:req_ai, :generate, :exception]` events.
  `ReqAI.stream/4` emits the same lifecycle events under `[:req_ai, :stream]`.
  Attach handlers with `:telemetry` to observe calls.

  The provider module is the default attribute extractor and may implement any
  of this module's optional callbacks. Pass `telemetry: MyApp.Telemetry` to
  `ReqAI.Provider.new/2` to select another extractor, or `telemetry: false` to
  disable emission. A `:telemetry_metadata` map adds static tags to events:

      ReqAI.Provider.new(ReqAI.Provider.OpenAI,
        telemetry_metadata: %{feature: :summarizer}
      )

  Metadata uses simple atom keys: `:operation`, `:provider`, `:model`,
  `:response_model`, `:finish_reasons`, `:input_tokens`, and `:output_tokens`.
  Extraction coverage varies by provider and request mode; attributes are
  included when available. Streaming calls also include `stream: true`.
  Stop metadata includes `:http_status` when an HTTP response is available,
  `:error`, and `:error_type` on errors.

  Stop measurements include `:duration`. Streaming stop measurements also
  include `:time_to_first_chunk` when a chunk was received, including a
  protocol-only event. Both measurements use native time units. Applications
  integrating with OpenTelemetry can map metadata to its semantic conventions
  in their handlers.

  Built-in extractors select operational attributes rather than recording
  request or response bodies. Custom extractors and static metadata control
  any additional data recorded. Exception events include the standard
  `:telemetry.span/3` exception metadata, which may contain exception details.
  """

  import ReqAI.Utils, only: [ensure_loaded!: 1, maybe_apply: 4]

  @callback request_metadata(
              metadata :: map(),
              request :: map() | keyword(),
              opts :: keyword()
            ) :: map()

  @callback response_metadata(
              metadata :: map(),
              Req.Response.t(),
              opts :: keyword()
            ) :: map()

  @callback event_metadata(
              metadata :: map(),
              event :: term(),
              response :: Req.Response.t(),
              opts :: keyword()
            ) :: map()

  @optional_callbacks request_metadata: 3, response_metadata: 3, event_metadata: 4

  @doc false
  def span(false, _metadata, _event_prefix, _request, _opts, fun) do
    {result, _measurements, _source} = fun.(nil)
    result
  end

  def span(telemetry, initial_metadata, event_prefix, request, opts, fun) do
    telemetry = ensure_loaded!(telemetry)
    streaming? = Keyword.fetch!(opts, :stream)
    metadata = start_metadata(telemetry, initial_metadata, request, opts)

    :telemetry.span(event_prefix, metadata, fn ->
      {result, measurements, response} = fun.(metadata)

      final_metadata =
        case {response, streaming?} do
          {{:ok, req_response, metadata}, false} ->
            stop_metadata(telemetry, metadata, req_response, opts)

          {{:ok, _req_response, metadata}, true} ->
            metadata

          {{:error, _exception, metadata}, _} ->
            metadata
        end

      {result, measurements, final_metadata}
    end)
  end

  @doc false
  def event_metadata(false, metadata, _event, _response, _opts) do
    metadata
  end

  def event_metadata(telemetry, metadata, event, response, opts) do
    maybe_apply(telemetry, :event_metadata, [metadata, event, response, opts], metadata)
  end

  defp start_metadata(telemetry, metadata, req_response, opts) do
    maybe_apply(telemetry, :request_metadata, [metadata, req_response, opts], metadata)
  end

  defp stop_metadata(telemetry, metadata, req_response, opts) do
    maybe_apply(telemetry, :response_metadata, [metadata, req_response, opts], metadata)
  end
end
