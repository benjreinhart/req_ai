defmodule ReqAI.Utils do
  @moduledoc false

  def ensure_loaded!(nil), do: nil
  def ensure_loaded!(module), do: Code.ensure_loaded!(module)

  def maybe_apply(module, fun, args, value) do
    if function_exported?(module, fun, length(args)) do
      apply(module, fun, args)
    else
      value
    end
  end
end
