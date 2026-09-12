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

  @optional_callbacks request_metadata: 3, response_metadata: 3

  @doc false
  def span(%Provider{telemetry: false}, _event_prefix, _request, _opts, fun) do
    {result, _source} = fun.()
    result
  end

  def span(%Provider{} = provider, event_prefix, request, opts, fun) do
    metadata = start_metadata(provider.telemetry, provider.telemetry_metadata, request, opts)

    :telemetry.span(event_prefix, metadata, fn ->
      {result, source} = fun.()
      {result, stop_metadata(provider.telemetry, metadata, source, opts)}
    end)
  end

  defp start_metadata(telemetry, metadata, request, opts) do
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

  defp stop_metadata(_telemetry, metadata, {:error, exception}, _opts) do
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
