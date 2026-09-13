defmodule ReqAI.Provider.Anthropic do
  @moduledoc """
  Provider-native adapter for Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils, only: [decode_json_sse: 1, set_stream: 2, fetch_attr: 2]

  @url "https://api.anthropic.com/v1/messages"

  @version "2023-06-01"
  @version_header "anthropic-version"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.Request.put_new_header(@version_header, @version)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end

  @impl true
  def decode_event(event, _response, _opts), do: decode_json_sse(event)

  @impl true
  def request_metadata(metadata, request, _opts) do
    metadata
    |> Map.put_new(:"gen_ai.operation.name", "chat")
    |> Map.put_new(:"gen_ai.provider.name", "anthropic")
    |> Map.put_new(:"gen_ai.request.model", fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    Map.put_new(metadata, :"gen_ai.response.model", fetch_attr(body, :model))
  end
end
