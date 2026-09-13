defmodule ReqAI.Telemetry do
  @moduledoc "Optional attribute extraction callbacks for telemetry events."

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
    {result, _source} = fun.(%{})
    result
  end

  def span(%Provider{} = provider, event_prefix, request, opts, fun) do
    metadata = start_metadata(provider.telemetry, provider.telemetry_metadata, request, opts)

    :telemetry.span(event_prefix, metadata, fn ->
      {result, source} = fun.(metadata)
      {result, stop_metadata(provider.telemetry, metadata, source, opts)}
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
    # From the otel genai semconv spec:
    # gen_ai.request.stream: If and only if the request is streaming. If unset, the request is assumed to be non-streaming.
    metadata =
      if opts[:stream] do
        Map.put(metadata, :"gen_ai.request.stream", true)
      else
        Map.delete(metadata, :"gen_ai.request.stream")
      end

    extract_metadata(telemetry, :request_metadata, [metadata, request, opts], metadata)
  end

  defp stop_metadata(telemetry, metadata, {:response, response, error?}, opts) do
    metadata =
      metadata
      |> Map.put(:"http.response.status_code", response.status)
      |> Map.put(:error, error?)
      |> maybe_put_error_type(response.status, error?)

    extract_metadata(telemetry, :response_metadata, [metadata, response, opts], metadata)
  end

  defp stop_metadata(_telemetry, _metadata, {:stream, response, error?, metadata}, _opts) do
    metadata
    |> Map.put(:"http.response.status_code", response.status)
    |> Map.put(:error, error?)
    |> maybe_put_error_type(response.status, error?)
  end

  defp stop_metadata(_telemetry, metadata, {:error, exception}, _opts) do
    metadata
    |> Map.put(:error, true)
    |> Map.put(:"error.type", error_type(exception))
  end

  defp stop_metadata(_telemetry, _metadata, {:stream_error, exception, metadata}, _opts) do
    metadata
    |> Map.put(:error, true)
    |> Map.put(:"error.type", error_type(exception))
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
    Map.put(metadata, :"error.type", Integer.to_string(status))
  end

  defp maybe_put_error_type(metadata, _status, _error?), do: metadata
end
