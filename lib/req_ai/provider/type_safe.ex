defmodule ReqAI.Provider.TypeSafe do
  @moduledoc """
  Provider-native adapter for TypeSafe's [System One API](https://docs.typesafe.ai/api).

      provider =
        ReqAI.Provider.new(ReqAI.Provider.TypeSafe,
          req: [auth: {:bearer, System.fetch_env!("TYPESAFE_API_KEY")}]
        )

      ReqAI.generate(provider, %{
        model: "jev-latest",
        state: "Please cancel my subscription.",
        questions: %{
          cancellation: %{
            type: "noul",
            instructions: "Is the customer requesting cancellation?"
          }
        }
      })

  Streaming is unsupported. `ReqAI.stream/4` raises `ArgumentError`
  before making an HTTP request.

  Telemetry uses `provider: "typesafe"` and `operation: "evaluate"`, with model
  and input/output token usage when available. No finish reasons are extracted.
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils

  @url "https://api.typesafe.ai/v1/systemone"

  @impl true
  def build(%Req.Request{} = req, request, _opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: json_object!(request))
  end

  @impl true
  def request_metadata(metadata, request, _opts) do
    metadata
    |> put_attr(:operation, "evaluate")
    |> put_attr(:provider, "typesafe")
    |> put_attr(:model, fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{status: status, body: body}, _opts)
      when status in 200..299 do
    metadata
    |> put_attr(:response_model, Map.get(body, "model"))
    |> put_attr(:input_tokens, get_in(body, ["usage", "input_tokens"]))
    |> put_attr(:output_tokens, get_in(body, ["usage", "output_tokens"]))
  end

  def response_metadata(metadata, %Req.Response{}, _opts), do: metadata
end
