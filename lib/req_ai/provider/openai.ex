defmodule ReqAI.Provider.OpenAI do
  @moduledoc """
  Provider-native adapter for the OpenAI [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils,
    only: [decode_json_sse: 1, set_stream: 2, fetch_attr: 2, put_attr: 3]

  @url "https://api.openai.com/v1/responses"

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
    |> put_attr(:"gen_ai.provider.name", "openai")
    |> put_attr(:"gen_ai.request.model", fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    put_attr(metadata, :"gen_ai.response.model", fetch_attr(body, :model))
  end

  @impl true
  def event_metadata(metadata, %{data: %{"response" => response}}, _, _) do
    metadata =
      case response do
        %{"model" => model} ->
          put_attr(metadata, :"gen_ai.response.model", model)

        _ ->
          metadata
      end

    case response do
      %{"usage" => %{"input_tokens" => input_tokens, "output_tokens" => output_tokens}} ->
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
