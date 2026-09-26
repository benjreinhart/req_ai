# Custom providers

To support a custom provider in your application, implement the `ReqAI.Provider` behaviour. This guide demonstrates how to do so using OpenAI's [Chat Completions API](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create) as an example.

## Implement the provider

Create `lib/my_app/providers/chat_completions.ex`:

```elixir
defmodule MyApp.Providers.ChatCompletions do
  @behaviour ReqAI.Provider

  @impl true
  def build(req, request, _opts) do
    body = request |> Map.new() |> Map.drop([:stream, "stream"]) |> Map.put(:stream, false)

    req
    |> Req.Request.put_new_option(:base_url, "https://api.openai.com/v1/chat/completions")
    |> Req.merge(method: :post, json: body)
  end
end
```

`build/3` receives the configured `Req.Request`, the request body, and provider options. It returns a request for ReqAI to execute. Extend the supplied `req` to preserve the caller's HTTP options.

`Map.new/1` accepts a map or keyword list and ensures the top-level JSON value is an object. This allows clients to pass a keyword list or map for convenience.

`put_new_option/3` supplies a default endpoint while allowing callers to override `:base_url`. Allowing these overrides is helpful in cases where you may want to dynamically point to different services that are compatible with the API, in this case, the Chat Completions format.

In this example, the provider forces `stream: false`, meaning this provider is unable to stream. We'll see how to add streaming support below.

## Call the provider

Configure authentication, then pass a model and messages to `ReqAI.generate/2`:

```elixir
provider =
  ReqAI.Provider.new(MyApp.Providers.ChatCompletions,
    req: [auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")}]
  )

request = %{
  model: "gpt-5.4-mini",
  messages: [%{role: "user", content: "Say hello"}]
}

{:ok, _response, body} = ReqAI.generate(provider, request)

[%{"message" => %{"content" => text}}] = body["choices"]
IO.puts(text)
```

Req decodes the JSON response into maps with string keys. This text-only example reads the single returned choice.

The example matches a successful response. ReqAI returns `{:error, response, body}` for non-2xx responses and `{:error, exception}` for errors returned by Req. See [Return values](getting-started.md#return-values) for error handling.

Custom providers use the same [application configuration](configuration.md) as built-in providers. Once HTTP options are configured under `MyApp.Providers.ChatCompletions`, you can pass that module directly to `ReqAI.generate/2`.

ReqAI emits lifecycle telemetry without additional callbacks. To add provider, model, or token-usage attributes, implement `ReqAI.Telemetry` on the provider or configure a separate extractor. See the [telemetry guide](telemetry.md).

## Add streaming

Update `build/3` to use `opts[:stream]`, which ReqAI sets to `false` for generation and `true` for streaming. Add `decode_event/3` to decode the SSE payloads. The complete provider becomes:

```elixir
defmodule MyApp.Providers.ChatCompletions do
  @behaviour ReqAI.Provider

  @impl true
  def build(req, request, opts) do
    body = request |> Map.new() |> Map.drop([:stream, "stream"]) |> Map.put(:stream, opts[:stream])

    req
    |> Req.Request.put_new_option(:base_url, "https://api.openai.com/v1/chat/completions")
    |> Req.merge(method: :post, json: body)
  end

  @impl true
  def decode_event(%{data: data}, _response, _opts) when data in ["", "[DONE]"] do
    []
  end

  def decode_event(%{data: data} = event, _response, _opts) do
    [%{event | data: JSON.decode!(data)}]
  end
end
```

Req handles SSE framing and passes event maps to the decoder. The decoder returns a list: `[]` discards empty data and the `[DONE]` marker; `[event]` delivers one event to the consumer. Here, JSON is decoded in `:data`, preserving the surrounding SSE fields. Invalid JSON raises and propagates to the caller.

Using the same `provider` and `request` from above, collect text from Chat Completions' `delta.content` field:

```elixir
{:ok, _response, chunks} =
  ReqAI.stream(provider, request, [], fn event, _response, chunks ->
    case event do
      %{data: %{"choices" => [%{"delta" => %{"content" => text}}]}}
      when is_binary(text) ->
        IO.write(text)
        {:cont, [text | chunks]}

      _ ->
        {:cont, chunks}
    end
  end)

text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
```

The callback returns `{:cont, chunks}` to continue, or can return `{:halt, chunks}` to stop early. This example collects text for a single choice and ignores other events, including tool calls and provider error payloads. The accumulated text is returned separately from the HTTP response; ReqAI does not assemble a completed Chat Completions response body.

## Skip decoding unwanted events

`decode_event/3` can discard events before calling `JSON.decode!/1`, avoiding JSON parsing work for events you do not need. For an API that sends named SSE events, add a clause before the JSON-decoding clause. For example, to skip `ping` events:

```elixir
def decode_event(%{event: "ping"}, _response, _opts), do: []
```

This works when you can identify the event from its SSE fields without inspecting the JSON payload. Chat Completions uses data-only events, so filtering by fields inside its JSON still requires decoding; the example above already skips its `[DONE]` marker before decoding.
