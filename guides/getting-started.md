# Getting Started

ReqAI provides a common calling convention on top of AI provider APIs. Pass a provider module or a configured `ReqAI.Provider` to `ReqAI.generate/2` or `ReqAI.stream/4`.

> #### Req compatibility {: .info}
>
> ReqAI depends on Req 0.8 and requires Elixir 1.18 or later.

## Configuring API keys

To call any provider, you'll need to configure it with an API key. You have two options.

First, you can use the application configuration. In `config/runtime.exs`:

```elixir
config :req_ai, :providers, [
  {ReqAI.Provider.OpenAI, req: [auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")}]}
]
```

Second, you can configure a provider directly in code. This is useful if you need to switch keys dynamically, or when working in scripts or without a Mix project:

```elixir
provider =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    req: [auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")}]
  )

ReqAI.generate(provider, request)
```

This guide assumes API keys are configured in the application configuration. Learn more in [Provider configuration](./configuration.md).

## Generate a response

At its simplest, ReqAI provides everything except an API key. The below example calls OpenAI:

```elixir
{:ok, %Req.Response{}, %{"output" => [%{"content" => [content]}]}} =
  ReqAI.generate(ReqAI.Provider.OpenAI,
    model: "gpt-5.4-mini",
    input: "Say hello"
  )

IO.puts(content["text"])
```

Notice the request body (the `model` and `input` keyword list) and response body are the same format as the underlying provider, in this case, OpenAI's [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create). By default, the request and response bodies will always match that of the underlying provider's API.

Here's another example, this time using Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create):

```elixir
{:ok, %Req.Response{}, %{"content" => [content]}} =
  ReqAI.generate(ReqAI.Provider.Anthropic,
    model: "claude-opus-5-5",
    max_tokens: 256,
    messages: [%{role: "user", content: "Say hello"}]
  )

IO.puts(content["text"])
```

ReqAI intentionally does not standardize provider request or response bodies. Instead, the code maps directly to the underlying provider API. If desired, you can bring your own request and response body abstraction by configuring a [translator](https://req-ai.hexdocs.pm/ReqAI.Translator.html).

## Stream a response

Streaming is supported using `ReqAI.stream/4`. For example, we can stream a haiku:

```elixir
request = %{
  model: "gpt-5.4-mini",
  input: "Write a Haiku"
}

{:ok, %Req.Response{}, haiku} =
  ReqAI.stream(ReqAI.Provider.OpenAI, request, [], fn event, %Req.Response{}, iodata ->
    case event do
      %{event: "response.output_text.delta", data: %{"delta" => delta}} ->
        IO.write(delta)
        {:cont, [iodata, delta]}

      %{event: "response.completed", data: %{"response" => %{"usage" => usage}}} ->
        IO.write("\n\n=== Total tokens: #{usage["total_tokens"]}\n")
        {:halt, IO.iodata_to_binary(iodata)}

      _ ->
        {:cont, iodata}
    end
  end)

IO.puts(haiku)
```

Streaming takes an `accum` and callback function. The function is passed the decoded `event`, the `%Req.Response{}`, and the `accum` (same as the underlying `Req.stream/4`).

ReqAI uses each provider's request and event formats. Built-in adapters convert keyword request bodies to maps. Streaming-capable adapters override the body's `stream` field: `false` for `ReqAI.generate/2`, `true` for `ReqAI.stream/4`. For SSE streams, they decode JSON payloads in the event's `:data` field and discard ping events, empty data, and `[DONE]` markers.

## Return values

The examples above match successful responses for brevity. Real application code will want to handle both success and failure cases.

```elixir
case ReqAI.generate(provider, request) do
  {:ok, _response, body} ->
    {:ok, body}

  {:error, response, body} ->
    {:error, {:http, response.status, body}}

  {:error, exception} ->
    {:error, {:request, Exception.message(exception)}}
end
```

There are two main differences here from `Req`'s return values:

1. Only 2xx responses are returned with `:ok` tuples. A 4xx or 5xx would be an `:error` tuple (the second branch above).
2. The `:ok` and `:error` tuples (non-exceptional) return a third argument. By default, it's the `body` of the `%Req.Response{}` struct. If using [translators](https://req-ai.hexdocs.pm/ReqAI.Translator.html), it would be the result of calling one of the translator behaviour callbacks.

An HTTP error, such as a 401 or 429, preserves the response and provider error body. A returned transport or decoding error carries an exception instead.

Streaming failures can include a partial response and the accumulator collected so far:

```elixir
case ReqAI.stream(provider, request, [], fun) do
  {:ok, response, chunks} ->
    text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, text, response.headers}

  {:error, response, body} ->
    {:error, {:http, response.status, body}}

  {:error, exception, response, chunks} ->
    partial_text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    {:error, {:request, Exception.message(exception), response, partial_text}}
end
```

On a non-successful HTTP response, ReqAI buffers the error body instead of passing it to your callback, decoding JSON when possible. On a returned transport or decoding failure, `response` may be `nil`, and `chunks` contains any text already collected.

These tuples describe HTTP and request outcomes. Providers may also report failures inside a successful HTTP response or streamed event. Inspect their native status fields and error events when your application needs to distinguish those outcomes; the text-only callbacks above ignore non-text events. Exceptions raised by your callbacks propagate to the caller.

Retries and timeouts are controlled by Req through `:req`. See `ReqAI.generate/2` and `ReqAI.stream/4` for the complete return contracts.
