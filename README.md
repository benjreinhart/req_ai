# ReqAI

ReqAI is a lightweight, extensible runtime for LLM APIs. It provides a common execution boundary for calling LLM-provider APIs without imposing a universal request and or response interface.

## Why ReqAI?

LLM APIs differ in important ways and evolve too quickly for a complete universal data model. ReqAI is designed to give applications one place for generation, streaming, monitoring, testing, policy, and extension without forcing inherently different APIs into lossy shared request and response types.

The current API is intentionally lower-level: callers configure adapters under `ReqAI.Provider` and pass provider-native request data. Applications can add their own unified representation as a layer on top where their requirements and supported providers are known.

## Design goals

- **Provider-native by default.** Requests, responses, and streamed events should retain the provider's shape so callers can use provider-specific features without clunky escape hatches or waiting for ReqAI to support them.
- **Extensible abstractions.** ReqAI does not define a universal LLM request or response. However, it supports a simple yet elegant pattern that applications and higher-level libraries can use to build this layer on top.
- **A consistent execution boundary.** Generation and streaming should have predictable control flow even when the data passing through them remains provider-specific.
- **Observability without accidental disclosure.** Model calls should be easy to monitor, while secrets and potentially sensitive request or response content are excluded unless deliberately recorded.
- **A small, approachable core.** Prefer simple values and focused adapters for well-supported APIs over a large model catalog or a deep hierarchy of custom types and behaviours.

## Custom representations

Applications can configure a module implementing the `ReqAI.Translator` behaviour to translate between application values and provider-native requests, responses, errors, and streamed events. Each callback is optional. Requests and events remain provider-native by default, while response and error values default to the provider-native response body.

For example, an application can design an `%LLMRequest{}` struct and translate it for both OpenAI and Anthropic:

```elixir
defmodule MyApp.Translator.OpenAI do
  @behaviour ReqAI.Translator

  @impl true
  def request(%MyApp.LLMRequest{} = request, _opts) do
    # transform the %LLMRequest{} to what OpenAI expects...
  end
end

defmodule MyApp.Translator.Anthropic do
  @behaviour ReqAI.Translator

  @impl true
  def request(%MyApp.LLMRequest{} = request, _opts) do
    # transform the %LLMRequest{} to what Anthropic expects...
  end
end

openai =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    model: "gpt-5.6-sol",
    translator: MyApp.Translator.OpenAI
  )

anthropic =
  ReqAI.Provider.new(ReqAI.Provider.Anthropic,
    model: "claude-haiku-4-5",
    translator: MyApp.Translator.Anthropic
  )

# Swap out provider/model depending on rate limits,
# provider availability, user preferences, etc.
provider = select_provider(user, [openai, anthropic])

{:ok, response, result} = ReqAI.generate(provider, %MyApp.LLMRequest{
  tokens: 200,
  transcript: [{:system, "Be nice"}, {:user, "Hello"}],
})
```

Translator callbacks receive the same provider options as `build/3`, including the final `:stream` value selected by `generate/2` or `stream/4`. `request/2` must return a provider-native map or keyword list. `response/2` produces the application value for successful calls to `generate/2`, while `error/2` produces it for non-successful HTTP responses from `generate/2` and `stream/4`. Both default to `response.body`. For successful streams, `event/3` translates each decoded event and the caller's accumulator is the application result.

Whenever an HTTP request completes, the untouched `Req.Response` is the second tuple element and the application-owned value is the third:

```elixir
{:ok, %Req.Response{} = response, result} = ReqAI.generate(provider, request)
{:error, %Req.Response{} = response, error} = ReqAI.generate(provider, request)
{:error, exception} = ReqAI.generate(provider, request)
```

A transport or decoding error has an exception in the second element instead. Streaming errors also include the response received so far (or `nil`) and the partially built accumulator.

## Telemetry

`generate/2` emits `[:req_ai, :generate, :start]`, `[:req_ai, :generate, :stop]`, and `[:req_ai, :generate, :exception]` events. The provider module is used as the telemetry extractor by default and may implement any of the optional `ReqAI.Telemetry` callbacks to add provider-specific attributes. Pass `telemetry: MyApp.Telemetry` to use a separate extractor, or `telemetry: false` to disable emission for that provider. A static metadata map can tag every event:

```elixir
ReqAI.Provider.new(ReqAI.Provider.OpenAI,
  telemetry_metadata: %{feature: :summarizer}
)
```

Applications can attach handlers with `:telemetry` without replacing the emission layer.

`stream/4` emits the same lifecycle events under `[:req_ai, :stream]`. Metadata
uses simple atom keys independent of OpenTelemetry semantic conventions:
`:operation`, `:provider`, `:model`, `:response_model`, `:finish_reasons`,
`:input_tokens`, and `:output_tokens`. Provider attributes are included when
available; extraction coverage varies by provider and request mode. Streaming
and non-streaming responses both report `:input_tokens` and `:output_tokens`
when the provider supplies usage. Streaming
requests also include `stream: true`. Stop metadata includes `:status_code` when
an HTTP response is available, `:error`, and `:error_type` on errors.

Streaming stop measurements include `:time_to_first_chunk` when a chunk was
received, in native time units like `:duration`. Applications integrating with
OpenTelemetry can map these keys to its semantic conventions in their handlers.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `req_ai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:req_ai, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/req_ai>.
