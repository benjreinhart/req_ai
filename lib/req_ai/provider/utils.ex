defmodule ReqAI.Provider.Utils do
  @moduledoc false

  def decode_json_sse(%{event: "ping"}), do: []
  def decode_json_sse(%{data: data}) when data in ["", "[DONE]"], do: []

  def decode_json_sse(%{data: data} = event) when is_binary(data) do
    case JSON.decode(data) do
      {:ok, json} ->
        [%{event | data: json}]

      {:error, _} ->
        raise %RuntimeError{message: "non-JSON SSE data #{inspect(data)}"}
    end
  end

  def decode_json_sse(_event), do: []

  def json_object!(request) when is_map(request) do
    request
  end

  def json_object!(request) do
    if Keyword.keyword?(request) do
      Map.new(request)
    else
      raise ArgumentError, "expected a request map or keyword list, got: #{inspect(request)}"
    end
  end

  def set_stream(request, value) when is_map(request) do
    Map.drop(request, [:stream, "stream"]) |> Map.put(:stream, value)
  end

  def fetch_attr(source, key) when is_map(source) and is_atom(key) do
    case Map.fetch(source, key) do
      {:ok, value} -> value
      :error -> Map.get(source, Atom.to_string(key))
    end
  end

  def fetch_attr(source, key) when is_list(source) and is_atom(key) do
    Keyword.get(source, key)
  end

  def put_attr(metadata, _key, nil), do: metadata
  def put_attr(metadata, key, value), do: Map.put(metadata, key, value)
end
