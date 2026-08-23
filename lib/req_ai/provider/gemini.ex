defmodule ReqAI.Provider.Gemini do
  @moduledoc """
  Provider-native adapter for Gemini's [Interactions API](https://ai.google.dev/api/interactions-api-v1).
  """

  @behaviour ReqAI.Provider

  import ReqAI.Provider.Utils, only: [set_stream: 2]

  @url "https://generativelanguage.googleapis.com/v1beta/interactions"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end
end
