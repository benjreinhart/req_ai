defmodule ReqAI.Provider.OpenAI do
  @moduledoc """
  Provider-native adapter for the OpenAI [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create).
  """

  @behaviour ReqAI.Provider

  import ReqAI.Provider.Utils, only: [set_stream: 2, fetch_attr: 2]

  @url "https://api.openai.com/v1/responses"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end

  @impl true
  def telemetry({:request, request}, opts) do
    %{
      "gen_ai.operation.name": "chat",
      "gen_ai.provider.name": "openai",
      "gen_ai.request.model": fetch_attr(request, :model),
      "gen_ai.request.stream": opts[:stream]
    }
  end

  def telemetry({:response, %Req.Response{body: body}}, _opts) do
    %{"gen_ai.response.model": fetch_attr(body, :model)}
  end
end
