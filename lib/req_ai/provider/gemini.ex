defmodule ReqAI.Provider.Gemini do
  @moduledoc """
  Provider-native adapter for Gemini's [Interactions API](https://ai.google.dev/api/interactions-api-v1).

  Configure API key authentication through Req:

      provider =
        ReqAI.Provider.new(ReqAI.Provider.Gemini,
          req: [headers: [{"x-goog-api-key", System.fetch_env!("GEMINI_API_KEY")}]]
        )

      ReqAI.generate(provider, %{model: "gemini-3.1-flash-lite", input: "Say hello"})

  Authentication and other `:req` options can also be set for this provider under
  `config :req_ai, :providers`. Options passed explicitly to `ReqAI.Provider.new/2`
  take precedence over application configuration.

  This adapter uses Interactions API bodies and events.
  """

  @behaviour ReqAI.Provider
  @behaviour ReqAI.Telemetry

  import ReqAI.Provider.Utils

  @url "https://generativelanguage.googleapis.com/v1beta/interactions"

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
    |> put_attr(:operation, "generate_content")
    |> put_attr(:provider, "gcp.gemini")
    |> put_attr(:model, fetch_attr(request, :model))
  end

  @impl true
  def response_metadata(metadata, %Req.Response{status: status, body: body}, _opts)
      when status in 200..299 do
    response_attributes(metadata, body)
  end

  def response_metadata(metadata, %Req.Response{}, _opts), do: metadata

  @impl true
  def event_metadata(metadata, %{data: %{"interaction" => interaction}}, _, _) do
    response_attributes(metadata, interaction)
  end

  @impl true
  def event_metadata(
        metadata,
        %{data: %{"event_type" => "interaction.status_update"} = data},
        _,
        _
      ) do
    put_attr(metadata, :finish_reasons, finish_reasons(data))
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata

  defp response_attributes(metadata, body) do
    metadata
    |> put_attr(:response_id, Map.get(body, "id"))
    |> put_attr(:response_model, Map.get(body, "model"))
    |> put_attr(:finish_reasons, finish_reasons(body))
    |> put_attr(:input_tokens, get_in(body, ["usage", "total_input_tokens"]))
    |> put_attr(
      :output_tokens,
      add_token_counts(get_in(body, ["usage", "total_output_tokens"]), [
        get_in(body, ["usage", "total_thought_tokens"])
      ])
    )
    |> put_attr(:cache_read_input_tokens, get_in(body, ["usage", "total_cached_tokens"]))
    |> put_attr(:reasoning_output_tokens, get_in(body, ["usage", "total_thought_tokens"]))
  end

  defp finish_reasons(%{"status" => status})
       when status in ["completed", "requires_action", "failed", "cancelled", "incomplete"],
       do: [status]

  defp finish_reasons(_body), do: nil
end
