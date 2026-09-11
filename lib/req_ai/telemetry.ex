defmodule ReqAI.Telemetry do
  @moduledoc false

  @doc false
  def telemetry(provider, source, opts) do
    provider.telemetry(source, opts) |> Enum.reject(&ignore?/1) |> Map.new()
  end

  defp ignore?({_key, nil}), do: true
  defp ignore?({:"gen_ai.request.stream", false}), do: true
  defp ignore?({_key, _value}), do: false
end
