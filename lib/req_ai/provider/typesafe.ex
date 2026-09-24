defmodule ReqAI.Provider.TypeSafe do
  @moduledoc """
  TypeSafe provider for the ReqAI library.

      provider =
        ReqAI.Provider.new(ReqAI.Provider.TypeSafe,
          req: [auth: {:bearer, System.fetch_env!("TYPESAFE_API_KEY")}]
        )

      ReqAI.generate(provider,
        state: "Hi, I've been trying to connect my Stripe account for 3 days and the integration keeps failing. I'm losing sales. Please help ASAP.",
        model: "jev-latest",
        questions: %{
          urgency: %{
            type: :noul,
            instructions: "Does this message express urgency?"
          }
        }
      )

  """

  @behaviour ReqAI.Provider

  import ReqAI.Provider.Utils, only: [json_object!: 1]

  @url "https://api.typesafe.ai/v1/systemone"

  @impl true
  def build(%Req.Request{} = req, request, _opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: json_object!(request))
  end
end
