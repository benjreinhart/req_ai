defmodule ReqAI.Provider.OpenAI do
  @moduledoc """
  Provider-native adapter for the OpenAI [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create).

  Configure bearer authentication through Req:

      provider =
        ReqAI.Provider.new(ReqAI.Provider.OpenAI,
          req: [auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")}]
        )

      ReqAI.generate(provider, %{model: "gpt-5.4-mini", input: "Say hello"})

  Authentication and other `:req` options can also be set for this provider under
  `config :req_ai, :providers`. Options passed explicitly to `ReqAI.Provider.new/2`
  take precedence over application configuration.

  This adapter uses Responses API bodies and events.
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils

  @url "https://api.openai.com/v1/responses"

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
    |> put_attr(:provider, "openai")
    |> put_attr(:model, fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{status: status, body: body}, _opts)
      when status in 200..299 do
    metadata
    |> put_attr(:response_model, Map.get(body, "model"))
    |> put_attr(:finish_reasons, finish_reasons(body))
    |> put_attr(:input_tokens, get_in(body, ["usage", "input_tokens"]))
    |> put_attr(:output_tokens, get_in(body, ["usage", "output_tokens"]))
  end

  def response_metadata(metadata, %Req.Response{}, _opts), do: metadata

  @impl true
  def event_metadata(metadata, %{data: %{"response" => response}}, _, _) do
    metadata = put_attr(metadata, :finish_reasons, finish_reasons(response))

    metadata =
      case response do
        %{"model" => model} ->
          put_attr(metadata, :response_model, model)

        _ ->
          metadata
      end

    case response do
      %{"usage" => %{"input_tokens" => input_tokens, "output_tokens" => output_tokens}} ->
        metadata
        |> put_attr(:input_tokens, input_tokens)
        |> put_attr(:output_tokens, output_tokens)

      _ ->
        metadata
    end
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata

  defp finish_reasons(%{"status" => status} = body)
       when status in ["completed", "failed", "cancelled", "incomplete"] do
    [get_in(body, ["incomplete_details", "reason"]) || status]
  end

  defp finish_reasons(_body), do: nil
end
