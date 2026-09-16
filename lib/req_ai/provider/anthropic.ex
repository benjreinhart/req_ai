defmodule ReqAI.Provider.Anthropic do
  @moduledoc """
  Provider-native adapter for Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create).
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils

  @url "https://api.anthropic.com/v1/messages"

  @version "2023-06-01"
  @version_header "anthropic-version"

  @impl true
  def build(%Req.Request{} = req, request, opts) do
    request = json_object!(request) |> set_stream(opts[:stream])

    req
    |> Req.Request.put_new_option(:base_url, @url)
    |> Req.Request.put_new_header(@version_header, @version)
    |> Req.merge(method: :post, json: request)
  end

  @impl true
  def decode_event(event, _response, _opts), do: decode_json_sse(event)

  @impl true
  def request_metadata(metadata, request, _opts) do
    metadata
    |> put_attr(:operation, "chat")
    |> put_attr(:provider, "anthropic")
    |> put_attr(:model, fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    usage = fetch_attr(body, :usage) || %{}

    metadata
    |> put_attr(:response_model, fetch_attr(body, :model))
    |> put_attr(:input_tokens, fetch_attr(usage, :input_tokens))
    |> put_attr(:output_tokens, fetch_attr(usage, :output_tokens))
  end

  @impl true
  def event_metadata(metadata, %{data: %{"type" => "message_start", "message" => message}}, _, _) do
    case message do
      %{"model" => model, "usage" => %{"input_tokens" => input_tokens}} ->
        metadata
        |> put_attr(:response_model, model)
        |> put_attr(:input_tokens, input_tokens)

      _ ->
        metadata
    end
  end

  @impl true
  def event_metadata(metadata, %{data: %{"type" => "message_delta"} = data}, _, _) do
    case data do
      %{
        "delta" => %{"stop_reason" => stop_reason},
        "usage" => %{"output_tokens" => output_tokens}
      } ->
        metadata
        |> put_attr(:finish_reasons, stop_reason && [stop_reason])
        |> put_attr(:output_tokens, output_tokens)

      _ ->
        metadata
    end
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata
end
