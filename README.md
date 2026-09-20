# ReqAI

ReqAI is a lightweight Elixir client for LLM APIs, built on [Req](https://github.com/wojtekmach/req). It provides consistent generation, streaming, and telemetry with provider-native requests and responses. Custom providers, telemetry, and request and response bodies are supported through optional behaviours.

```elixir
{:ok, %Req.Response{}, body} =
  ReqAI.Provider.OpenAI
  |> ReqAI.Provider.new(telemetry_metadata: %{conversation_id: UUIDv7.generate()})
  |> ReqAI.generate(model: "gpt-5.4-mini", input: "Say hello")

%{"output" => [%{"content" => [%{"text" => text}]}]} = body

IO.puts(text)
```

## Philosophy

* **Don't unify request and response bodies.** Providers are already too different and they diverge further every month. Don't force users into a poor abstraction.
* **Stay small.** The library should be small, with few dependencies and abstractions. Include a handful of popular providers, but leave the rest to users.
* **Be easy to extend.** Cover the common cases well, then get out of the way. Integrating applications know their needs much better than a general purpose library does. Allow them to bring their own abstractions.
* **Treat observability as a first-class feature.** Telemetry is tedious. The library should ship the important parts and make the rest easy to add.

## Features

- Generate and stream with one calling convention across providers
- Adapters for Anthropic, OpenAI, Gemini, xAI, and OpenRouter. BYO using the [Provider](lib/req_ai/provider.ex) behaviour
- Telemetry for lifecycle, duration, token usage, time to first chunk, etc. BYO using the [Telemetry](lib/req_ai/provider.ex) behaviour
- Full control of the underlying Req client: auth, retries, timeouts, testing
- Optional [translators](lib/req_ai/translator.ex) for your own request, response, error, and event shapes

## Streaming

Use the same provider and request with a callback that receives each decoded event and updates an accumulator:

```elixir
{:ok, response, events} =
  ReqAI.stream(provider, request, [], fn event, _response, events ->
    {:cont, [event | events]}
  end)

events = Enum.reverse(events)
```

Return `{:halt, acc}` to stop consuming the stream. Events retain the provider's structure, with SSE JSON payloads decoded in `event.data`.

## Installation

Add ReqAI to your dependencies in `mix.exs`:

```elixir
{:req_ai, github: "benjreinhart/req_ai"}
```

Requires Elixir 1.18 or later.
