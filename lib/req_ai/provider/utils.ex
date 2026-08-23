defmodule ReqAI.Provider.Utils do
  @moduledoc false

  def set_stream(request, value) when is_map(request) do
    Map.drop(request, [:stream, "stream"]) |> Map.put(:stream, value)
  end

  def set_stream(request, value) when is_list(request) do
    Keyword.put(request, :stream, value)
  end
end
