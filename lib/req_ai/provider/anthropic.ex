defmodule ReqAI.Provider.Anthropic do
  @moduledoc """
  Provider-native adapter for Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create).

  Sets the `anthropic-version: 2023-06-01` header unless explicitly overridden.
  Configure API key authentication through Req:

      provider =
        ReqAI.Provider.new(ReqAI.Provider.Anthropic,
          req: [headers: [{"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")}]]
        )

      ReqAI.generate(provider, %{
        model: "claude-sonnet-4-6",
        max_tokens: 256,
        messages: [%{role: "user", content: "Say hello"}]
      })

  Authentication and other `:req` options can also be set for this provider under
  `config :req_ai, :providers`. Options passed explicitly to `ReqAI.Provider.new/2`
  take precedence over application configuration.
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
  def response_metadata(metadata, %Req.Response{status: status, body: body}, _opts)
      when status in 200..299 do
    stop_reason = Map.get(body, "stop_reason")

    metadata
    |> put_attr(:response_model, Map.get(body, "model"))
    |> put_attr(:finish_reasons, stop_reason && [stop_reason])
    |> put_attr(:input_tokens, get_in(body, ["usage", "input_tokens"]))
    |> put_attr(:output_tokens, get_in(body, ["usage", "output_tokens"]))
  end

  def response_metadata(metadata, %Req.Response{}, _opts), do: metadata

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
    stop_reason = get_in(data, ["delta", "stop_reason"])

    metadata
    |> put_attr(:finish_reasons, stop_reason && [stop_reason])
    |> put_attr(:output_tokens, get_in(data, ["usage", "output_tokens"]))
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata
end
