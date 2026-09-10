defmodule ReqAI.Provider.Utils do
  @moduledoc false

  def set_stream(request, value) when is_map(request) do
    Map.drop(request, [:stream, "stream"]) |> Map.put(:stream, value)
  end

  def set_stream(request, value) when is_list(request) do
    Keyword.put(request, :stream, value)
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
end
