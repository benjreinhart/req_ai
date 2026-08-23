defmodule ReqAI.Provider.OpenAI do
  @moduledoc """
  Provider-native adapter for the OpenAI [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create).
  """

  @behaviour ReqAI.Provider

  import ReqAI.Provider.Utils, only: [set_stream: 2]

  @url "https://api.openai.com/v1/responses"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end
end
