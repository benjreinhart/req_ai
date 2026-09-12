defmodule ReqAI.Telemetry do
  @moduledoc "Attribute extraction for telemetry events."

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
    apply(telemetry, :request_metadata, [metadata, request, opts])
  end

  defp stop_metadata(telemetry, metadata, {:response, response, error?}, opts) do
    metadata =
      metadata
      |> Map.put(:"http.response.status_code", response.status)
      |> Map.put(:error, error?)
      |> maybe_put_error_type(response.status, error?)

    apply(telemetry, :response_metadata, [metadata, response, opts])
  end

  defp stop_metadata(_telemetry, metadata, {:error, exception}, _opts) do
    metadata
    |> Map.put(:error, true)
    |> Map.put(:"error.type", error_type(exception))
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
