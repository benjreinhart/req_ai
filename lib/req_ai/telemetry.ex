defmodule ReqAI.Telemetry do
  @moduledoc false

  def request_metadata(provider, request, opts) do
    provider_metadata(provider, {:request, request}, opts)
  end

  def response_metadata(provider, metadata, response, opts, error?) do
    metadata
    |> Map.merge(provider_metadata(provider, {:response, response}, opts))
    |> Map.put(:"http.response.status_code", response.status)
    |> Map.put(:error, error?)
    |> maybe_put_error_type(response.status, error?)
  end

  def error_metadata(metadata, exception) do
    error_type =
      case exception do
        %Req.TransportError{reason: reason} when is_atom(reason) ->
          Atom.to_string(reason)

        %{__struct__: module} ->
          inspect(module)
      end

    metadata
    |> Map.put(:error, true)
    |> Map.put(:"error.type", error_type)
  end

  defp provider_metadata(provider, source, opts) do
    provider.telemetry(source, opts) |> Enum.reject(&ignore?/1) |> Map.new()
  end

  defp maybe_put_error_type(metadata, status, true) when is_integer(status) do
    Map.put(metadata, :"error.type", Integer.to_string(status))
  end

  defp maybe_put_error_type(metadata, _status, _error?), do: metadata

  defp ignore?({_key, nil}), do: true
  defp ignore?({:"gen_ai.request.stream", false}), do: true
  defp ignore?({_key, _value}), do: false
end
