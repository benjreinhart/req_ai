defmodule ReqAI.Provider.OpenRouter do
  @moduledoc """
  Provider-native adapter for OpenRouter's [Chat Completions API](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils

  @url "https://openrouter.ai/api/v1/chat/completions"

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
    |> put_attr(:provider, "openrouter")
    |> put_attr(:model, fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{status: status, body: body}, _opts)
      when status in 200..299 do
    metadata
    |> put_attr(:response_model, Map.get(body, "model"))
    |> put_attr(:finish_reasons, finish_reasons(body))
    |> put_attr(:input_tokens, get_in(body, ["usage", "prompt_tokens"]))
    |> put_attr(:output_tokens, get_in(body, ["usage", "completion_tokens"]))
  end

  def response_metadata(metadata, %Req.Response{}, _opts), do: metadata

  @impl true
  def event_metadata(metadata, %{data: data}, _, _) when is_map(data) do
    metadata =
      case data do
        %{"model" => model} ->
          put_attr(metadata, :response_model, model)

        _ ->
          metadata
      end

    metadata = put_attr(metadata, :finish_reasons, finish_reasons(data))

    case data do
      %{"usage" => %{"prompt_tokens" => input_tokens, "completion_tokens" => output_tokens}} ->
        metadata
        |> put_attr(:input_tokens, input_tokens)
        |> put_attr(:output_tokens, output_tokens)

      _ ->
        metadata
    end
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata

  defp finish_reasons(%{"choices" => choices}) when is_list(choices) do
    reasons = for %{"finish_reason" => reason} <- choices, not is_nil(reason), do: reason
    if reasons != [], do: reasons
  end

  defp finish_reasons(_body), do: nil
end
