defmodule ReqAI.Provider.XAI do
  @moduledoc """
  Provider-native adapter for xAI's [Responses API](https://docs.x.ai/developers/rest-api-reference/inference/chat#create-new-response).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils, only: [set_stream: 2, fetch_attr: 2]

  @url "https://api.x.ai/v1/responses"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end

  @impl true
  def request_metadata(metadata, request, opts) do
    Map.merge(
      %{
        "gen_ai.operation.name": "chat",
        "gen_ai.provider.name": "x_ai",
        "gen_ai.request.model": fetch_attr(request, :model),
        "gen_ai.request.stream": opts[:stream]
      },
      metadata
    )
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    Map.merge(%{"gen_ai.response.model": fetch_attr(body, :model)}, metadata)
  end

  @impl true
  def exception_metadata(metadata, _exception, _opts), do: metadata
end
