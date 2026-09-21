defmodule ReqAI.Provider.XAI do
  @moduledoc """
  Provider-native adapter for xAI's [Responses API](https://docs.x.ai/developers/rest-api-reference/inference/chat#create-new-response).
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

  defp finish_reasons(%{"status" => status}) when status in ["completed", "incomplete"],
    do: [status]

  defp finish_reasons(_body), do: nil
end
