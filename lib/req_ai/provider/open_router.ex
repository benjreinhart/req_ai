defmodule ReqAI.Provider.OpenRouter do
  @moduledoc """
  Provider-native adapter for OpenRouter's [Chat Completions API](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils,
    only: [decode_json_sse: 1, set_stream: 2, fetch_attr: 2, put_attr: 3]

  @url "https://openrouter.ai/api/v1/chat/completions"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.merge(method: :post, json: set_stream(request, opts[:stream]))
  end

  @impl true
  def decode_event(event, _response, _opts), do: decode_json_sse(event)

  @impl true
  def request_metadata(metadata, request, _opts) do
    metadata
    |> put_attr(:"gen_ai.operation.name", "chat")
    |> put_attr(:"gen_ai.provider.name", "openrouter")
    |> put_attr(:"gen_ai.request.model", fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    put_attr(metadata, :"gen_ai.response.model", fetch_attr(body, :model))
  end

  @impl true
  def event_metadata(metadata, %{data: data}, _, _) when is_map(data) do
    metadata =
      case data do
        %{"model" => model} ->
          put_attr(metadata, :"gen_ai.response.model", model)

        _ ->
          metadata
      end

    finish_reasons =
      case data do
        %{"choices" => choices} ->
          for %{"finish_reason" => finish_reason} <- choices,
              not is_nil(finish_reason),
              do: finish_reason

        _ ->
          []
      end

    metadata =
      case finish_reasons do
        [] -> metadata
        finish_reasons -> put_attr(metadata, :"gen_ai.response.finish_reasons", finish_reasons)
      end

    case data do
      %{"usage" => %{"prompt_tokens" => input_tokens, "completion_tokens" => output_tokens}} ->
        metadata
        |> put_attr(:"gen_ai.usage.input_tokens", input_tokens)
        |> put_attr(:"gen_ai.usage.output_tokens", output_tokens)

      _ ->
        metadata
    end
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata
end
