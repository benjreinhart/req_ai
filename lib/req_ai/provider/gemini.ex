defmodule ReqAI.Provider.Gemini do
  @moduledoc """
  Provider-native adapter for Gemini's [Interactions API](https://ai.google.dev/api/interactions-api-v1).
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
  def response_metadata(metadata, %Req.Response{body: body}, _opts) do
    put_attr(metadata, :response_model, fetch_attr(body, :model))
  end

  @impl true
  def event_metadata(metadata, %{data: %{"interaction" => interaction}}, _, _) do
    metadata =
      case interaction do
        %{"model" => model} ->
          put_attr(metadata, :response_model, model)

        _ ->
          metadata
      end

    case interaction do
      %{
        "usage" => %{
          "total_input_tokens" => input_tokens,
          "total_output_tokens" => output_tokens
        }
      } ->
        metadata
        |> put_attr(:input_tokens, input_tokens)
        |> put_attr(:output_tokens, output_tokens)

      _ ->
        metadata
    end
  end

  @impl true
  def event_metadata(metadata, _event, _response, _opts), do: metadata
end
