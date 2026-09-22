# Getting Started

ReqAI provides a common calling convention for LLM APIs while preserving each provider's request and response formats. You configure a provider, pass it a native request body, and either generate a response or consume streamed events.

> #### Req compatibility {: .info}
>
> ReqAI depends on Req 0.8 and requires Elixir 1.18 or later.

## Configure providers

`ReqAI.Provider.new/2` accepts a provider module and options. HTTP configuration goes under `:req`: authentication, headers, timeouts, retries, and other options supported by `Req.new/2`.

You can set application defaults, supply options when creating a provider, or combine the two.

### Application configuration

Set shared HTTP options for each provider in `config/config.exs`:

```elixir
import Config

config :req_ai, :providers, [
  {ReqAI.Provider.OpenAI, req: [receive_timeout: 60_000]},
  {ReqAI.Provider.Anthropic, req: [receive_timeout: 60_000]}
]
```

Read credentials at application startup in `config/runtime.exs`:

```elixir
import Config

config :req_ai, :providers, [
  {ReqAI.Provider.OpenAI,
   req: [auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")}]},
  {ReqAI.Provider.Anthropic,
   req: [headers: [{"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")}]]}
]
```

Elixir merges these keyword configurations, so the runtime credentials are combined with the timeouts from `config/config.exs`.

Create providers using those defaults:

```elixir
openai = ReqAI.Provider.new(ReqAI.Provider.OpenAI)
anthropic = ReqAI.Provider.new(ReqAI.Provider.Anthropic)
```

The built-in adapters supply their API endpoints. The Anthropic adapter also supplies the `anthropic-version: 2023-06-01` header unless you override it.

### Configure a provider directly

You can instead pass the same HTTP options directly to `ReqAI.Provider.new/2`, without application configuration:

```elixir
openai =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    req: [
      auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")},
      receive_timeout: 60_000
    ]
  )

anthropic =
  ReqAI.Provider.new(ReqAI.Provider.Anthropic,
    req: [
      headers: [{"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")}],
      receive_timeout: 60_000
    ]
  )
```

ReqAI does not automatically read API key environment variables. These examples explicitly read them and pass their values to Req.

### Override request configuration

Options passed when creating a provider take precedence over its application defaults. For example, keep the configured credentials but use a longer receive timeout and disable retries:

```elixir
openai =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    req: [receive_timeout: 120_000, retry: false]
  )
```

Options are merged by Req, e.g., explicitly supplied headers replace the configured value for that name.

To use an API-compatible proxy, override `:base_url` with the full endpoint, including its path:

```elixir
proxied_openai =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    req: [base_url: "https://llm-proxy.example.com/v1/responses"]
  )
```

### HTTP options and body parameters

Put HTTP options under `:req` when creating the provider. Put model names and other API body parameters in the request passed to `ReqAI.generate/2` or `ReqAI.stream/4`.

Arbitrary options can be passed to `ReqAI.Provider.new/2`. These will later be passed to the provider, telemetry, and translator modules when their callbacks are invoked. This enables clients to supply runtime configuration when desired.

## Generate a response

OpenAI's [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create) accepts `input`:

```elixir
openai_request = %{
  model: "gpt-5.4-mini",
  input: "Explain pattern matching in one sentence."
}

{:ok, %Req.Response{}, body} = ReqAI.generate(openai, openai_request)

%{"output" => [%{"content" => [%{"text" => text}]}]} = body

IO.puts(text)
```

Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create) accepts `messages` and requires `max_tokens`:

```elixir
anthropic_request = %{
  model: "claude-sonnet-4-6",
  max_tokens: 256,
  messages: [%{role: "user", content: "Explain pattern matching in one sentence."}]
}

{:ok, response, body} = ReqAI.generate(anthropic, anthropic_request)

%{"content" => [%{"text" => text}]} = body

IO.puts(text)
```

Choose a model available to your account. Requests can be maps or keyword lists. ReqAI sets the `stream` body parameter for you.

On HTTP success, the result is `{:ok, response, body}`. `response` is the full `Req.Response`, including status and headers; `body` is its decoded provider-native body unless you configure a translator. These examples extract text blocks while leaving other output available in `body`.

## Stream a response

Pass the same request to `ReqAI.stream/4`, along with an initial accumulator and a callback. The callback receives a decoded event, the in-progress response, and the accumulator. Return `{:cont, acc}` to continue or `{:halt, acc}` to stop consuming the stream.

For OpenAI, collect text deltas and print them as they arrive:

```elixir
collect_openai = fn
  %{data: %{"type" => "response.output_text.delta", "delta" => text}}, _response, chunks ->
    IO.write(text)
    {:cont, [text | chunks]}

  _event, _response, chunks ->
    {:cont, chunks}
end

{:ok, response, chunks} = ReqAI.stream(openai, openai_request, [], collect_openai)
text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
```

Anthropic has a different event shape:

```elixir
collect_anthropic = fn
  %{data: %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}}},
  _response,
  chunks ->
    IO.write(text)
    {:cont, [text | chunks]}

  _event, _response, chunks ->
    {:cont, chunks}
end

{:ok, response, chunks} = ReqAI.stream(anthropic, anthropic_request, [], collect_anthropic)
text = chunks |> Enum.reverse() |> IO.iodata_to_binary()
```

For both adapters, SSE events remain maps with JSON decoded into `event.data`. Protocol-only events such as keepalives are dropped. Other events keep their provider-native structure; the callbacks above only collect text.

The final third tuple element is your accumulator. ReqAI does not assemble a complete provider response from streamed events. Halting returns the accumulated value on an otherwise successful HTTP response; it does not imply the model finished generating.

## Handle errors

The examples above match successful responses for brevity. In application code, handle both non-successful HTTP responses and failures without a completed response:

```elixir
case ReqAI.generate(openai, openai_request) do
  {:ok, response, body} ->
    {:ok, body, response.headers}

  {:error, response, body} ->
    {:error, {:http, response.status, body}}

  {:error, exception} ->
    {:error, {:request, Exception.message(exception)}}
end
```

An HTTP error, such as a 401 or 429, preserves the response and provider error body. A returned transport or decoding error carries an exception instead.

Streaming failures can include a partial response and the accumulator collected so far:

```elixir
case ReqAI.stream(openai, openai_request, [], collect_openai) do
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
