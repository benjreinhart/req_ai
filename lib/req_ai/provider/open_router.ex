defmodule ReqAI.Provider.OpenRouter do
  @moduledoc """
  Provider-native adapter for OpenRouter's [Chat Completions API](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils, only: [decode_json_sse: 1, set_stream: 2, fetch_attr: 2]

  @url "https://openrouter.ai/api/v1/chat/completions"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end

  @impl true
  def decode_event(event, _response, _opts), do: decode_json_sse(event)

  @impl true
  def request_metadata(metadata, request, _opts) do
    metadata
    |> Map.put_new(:"gen_ai.operation.name", "chat")
    |> Map.put_new(:"gen_ai.provider.name", "openrouter")
    |> Map.put_new(:"gen_ai.request.model", fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    Map.put_new(metadata, :"gen_ai.response.model", fetch_attr(body, :model))
  end
end
