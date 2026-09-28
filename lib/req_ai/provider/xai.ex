defmodule ReqAI.Provider.XAI do
  @moduledoc """
  Provider-native adapter for xAI's [Responses API](https://docs.x.ai/developers/rest-api-reference/inference/chat#create-new-response).

  Configure bearer authentication through Req:

      provider =
        ReqAI.Provider.new(ReqAI.Provider.XAI,
          req: [auth: {:bearer, System.fetch_env!("XAI_API_KEY")}]
        )

      ReqAI.generate(provider, %{model: "grok-4.3", input: "Say hello"})

  Authentication and other `:req` options can also be set for this provider under
  `config :req_ai, :providers`. Options passed explicitly to `ReqAI.Provider.new/2`
  take precedence over application configuration.

  This adapter uses Responses API bodies and events.
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils

  @url "https://api.x.ai/v1/responses"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    request = json_object!(request) |> set_stream(opts[:stream])

    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: request)
  end

  @impl true
  def decode_event(event, _response, _opts), do: decode_json_sse(event)

  @impl true
  def request_metadata(metadata, request, _opts) do
    metadata
    |> put_attr(:operation, "chat")
    |> put_attr(:provider, "x_ai")
    |> put_attr(:model, fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{status: status, body: body}, _opts)
      when status in 200..299 do
    response_attributes(metadata, body)
  end

  def response_metadata(metadata, %Req.Response{}, _opts), do: metadata

  @impl true
  def event_metadata(metadata, %{data: %{"response" => response}}, _, _) do
    response_attributes(metadata, response)
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata

  defp response_attributes(metadata, body) do
    metadata
    |> put_attr(:response_id, Map.get(body, "id"))
    |> put_attr(:response_model, Map.get(body, "model"))
    |> put_attr(:finish_reasons, finish_reasons(body))
    |> put_attr(:input_tokens, get_in(body, ["usage", "input_tokens"]))
    |> put_attr(:output_tokens, get_in(body, ["usage", "output_tokens"]))
    |> put_attr(
      :cache_read_input_tokens,
      get_in(body, ["usage", "input_tokens_details", "cached_tokens"])
    )
    |> put_attr(
      :reasoning_output_tokens,
      get_in(body, ["usage", "output_tokens_details", "reasoning_tokens"])
    )
  end

  defp finish_reasons(%{"status" => status}) when status in ["completed", "incomplete"],
    do: [status]

  defp finish_reasons(_body), do: nil
end
