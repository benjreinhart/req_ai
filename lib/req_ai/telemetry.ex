defmodule ReqAI.Telemetry do
  @moduledoc """
  Optional attribute extraction callbacks for telemetry events.

  Built-in extractors use simple atom keys: `:operation`, `:provider`, `:model`,
  `:response_model`, `:finish_reasons`, `:input_tokens`, and `:output_tokens`.
  Attributes are included when available from the provider's response or stream
  events; extraction coverage varies by provider and request mode.

  The emission layer adds `:stream` (only for streaming requests), `:status_code`
  when an HTTP response is available, `:error`, and `:error_type` on errors.
  Streaming stop events also include a `:time_to_first_chunk` measurement when
  a chunk was received, in native time units like `:duration`.

  These names are independent of OpenTelemetry semantic conventions. Applications
  can map them to those conventions in their telemetry handlers.
  """

  alias ReqAI.Provider

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

  @doc """
  Called for each decoded stream event (the output of `decode_event/3`). Fold
  attributes that only exist in the event stream, such as the response model,
  finish reason, and usage.
  """
  @callback event_metadata(
              metadata :: map(),
              event :: term(),
              response :: Req.Response.t(),
              opts :: keyword()
            ) :: map()

  @optional_callbacks request_metadata: 3, response_metadata: 3, event_metadata: 4

  @doc false
  def span(%Provider{telemetry: false}, _event_prefix, _request, _opts, fun) do
    {result, _measurements, _source} = fun.(%{})
    result
  end

  def span(%Provider{} = provider, event_prefix, request, opts, fun) do
    metadata = start_metadata(provider.telemetry, provider.telemetry_metadata, request, opts)

    :telemetry.span(event_prefix, metadata, fn ->
      {result, measurements, source} = fun.(metadata)

      {result, measurements, stop_metadata(provider.telemetry, metadata, source, opts)}
    end)
  end

  @doc false
  def event_metadata(false, metadata, _event, _response, _opts), do: metadata

  def event_metadata(telemetry, metadata, event, response, opts) do
    extract_metadata(
      telemetry,
      :event_metadata,
      [metadata, event, response, opts],
      metadata
    )
  end

  defp start_metadata(telemetry, metadata, request, opts) do
    # Include the stream flag only for streaming requests.
    metadata =
      if opts[:stream] do
        Map.put(metadata, :stream, true)
      else
        Map.delete(metadata, :stream)
      end

    extract_metadata(telemetry, :request_metadata, [metadata, request, opts], metadata)
  end

  defp stop_metadata(telemetry, metadata, {:response, response, error?}, opts) do
    metadata =
      metadata
      |> Map.put(:status_code, response.status)
      |> Map.put(:error, error?)
      |> maybe_put_error_type(response.status, error?)

    extract_metadata(telemetry, :response_metadata, [metadata, response, opts], metadata)
  end

  defp stop_metadata(_telemetry, _metadata, {:stream, response, error?, metadata}, _opts) do
    metadata
    |> Map.put(:status_code, response.status)
    |> Map.put(:error, error?)
    |> maybe_put_error_type(response.status, error?)
  end

  defp stop_metadata(_telemetry, metadata, {:error, exception}, _opts) do
    metadata
    |> Map.put(:error, true)
    |> Map.put(:error_type, error_type(exception))
  end

  defp stop_metadata(_telemetry, _metadata, {:stream_error, exception, metadata}, _opts) do
    metadata
    |> Map.put(:error, true)
    |> Map.put(:error_type, error_type(exception))
  end

  defp extract_metadata(telemetry, callback, args, metadata) do
    case Code.ensure_loaded(telemetry) do
      {:module, ^telemetry} ->
        if function_exported?(telemetry, callback, length(args)) do
          apply(telemetry, callback, args)
        else
          metadata
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load telemetry module #{inspect(telemetry)}: #{inspect(reason)}"
    end
  end

  def error_type(%Req.TransportError{reason: reason}) when is_atom(reason) do
    Atom.to_string(reason)
  end

  def error_type(%{__struct__: module}) do
    inspect(module)
  end

  defp maybe_put_error_type(metadata, status, true) when is_integer(status) do
    Map.put(metadata, :error_type, Integer.to_string(status))
  end

  defp maybe_put_error_type(metadata, _status, _error?), do: metadata
end
