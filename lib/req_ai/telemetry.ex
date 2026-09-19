defmodule ReqAI.Telemetry do
  @moduledoc """
  Attribute extraction callbacks for telemetry events.
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
