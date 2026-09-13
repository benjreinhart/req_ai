defmodule ReqAI.Provider.OpenAI do
  @moduledoc """
  Provider-native adapter for the OpenAI [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils, only: [decode_json_sse: 1, set_stream: 2, fetch_attr: 2]

  @url "https://api.openai.com/v1/responses"

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
    Map.merge(
      %{
        "gen_ai.operation.name": "chat",
        "gen_ai.provider.name": "openai",
        "gen_ai.request.model": fetch_attr(request, :model)
      },
      metadata
    )
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    Map.merge(%{"gen_ai.response.model": fetch_attr(body, :model)}, metadata)
  end
end
