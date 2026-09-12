defmodule ReqAI.Provider.Gemini do
  @moduledoc """
  Provider-native adapter for Gemini's [Interactions API](https://ai.google.dev/api/interactions-api-v1).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils, only: [set_stream: 2, fetch_attr: 2]

  @url "https://generativelanguage.googleapis.com/v1beta/interactions"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end

  @impl true
  def request_metadata(request, opts) do
    %{
      "gen_ai.operation.name": "generate_content",
      "gen_ai.provider.name": "gcp.gemini",
      "gen_ai.request.model": fetch_attr(request, :model),
      "gen_ai.request.stream": opts[:stream]
    }
  end

  @impl true
  def response_metadata(%Req.Response{body: body}, _opts) do
    %{"gen_ai.response.model": fetch_attr(body, :model)}
  end
end
