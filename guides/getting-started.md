# Getting Started

ReqAI provides a common calling convention on top of LLM provider APIs. You configure a `ReqAI.Provider` and then invoke it using `ReqAI.generate/2` or `ReqAI.stream/4`.

> #### Req compatibility {: .info}
>
> ReqAI depends on Req 0.8 and requires Elixir 1.18 or later.

## Generate a response

At its simplest, ReqAI provides everything except an API key. The below example calls OpenAI:

```elixir
provider =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    req: [auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")}]
  )

{:ok, %Req.Response{}, body} =
  ReqAI.generate(provider, model: "gpt-5.4-mini", input: "Say hello")

%{"output" => [%{"content" => [%{"text" => text}]}]} = body

IO.puts(text)
```

Notice the request body (the `model` and `input` keyword list) and response body are the same format as the underlying provider, in this case, the [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create). By default, the request and response bodies will always match that of the underlying provider's API.

Here's another example, this time using Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create):

```elixir
provider =
  ReqAI.Provider.new(ReqAI.Provider.Anthropic,
    req: [headers: [{"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")}]]
  )

{:ok, %Req.Response{}, body} =
  ReqAI.generate(provider,
    model: "claude-sonnet-4-6",
    max_tokens: 256,
    messages: [%{role: "user", content: "Say hello"}]
  )

%{"content" => [%{"text" => text}]} = body

IO.puts(text)
```

ReqAI intentionally does not standardize provider request or response bodies. However, users of this library can bring their own request and response body abstraction by configuring a [translator](https://req-ai.hexdocs.pm/ReqAI.Translator.html).

> #### Configuration {: .info}
>
> You can also configure providers in your application config, e.g., config/runtime.exs. See [Configuration](configuration.md)

## Stream a response

Streaming is supported using `ReqAI.stream/4`. Using the same OpenAI provider from before, we can stream a haiku:

```elixir
request = %{
  model: "gpt-5.4-mini",
  input: "Write a Haiku"
}

{:ok, %Req.Response{}, haiku} =
  ReqAI.stream(provider, request, [], fn event, %Req.Response{}, iodata ->
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

Just as in `ReqAI.generate/2`, `ReqAI.stream/4` passes the request and response bodies through unmodified.

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
