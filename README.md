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

## Custom request representations

Providers can implement `prepare_request/2`, which receives the caller's input and the configured provider options before `build/3` constructs the HTTP request. This enables applications to build a shared interface for AI provider requests. You can imagine designing an `%LLMRequest{}` struct and using it for both OpenAI and Anthropic. For example:

```elixir
defmodule MyApp.Provider.OpenAI do
  @behaviour ReqAI.Provider

  @impl true
  def prepare_request(%MyApp.LLMRequest{} = request, _opts) do
    # transform the %LLMRequest{} to what OpenAI expects...
  end

  @impl true
  defdelegate build(req, request, opts), to: ReqAI.Provider.OpenAI
end

defmodule MyApp.Provider.Anthropic do
  @behaviour ReqAI.Provider

  @impl true
  def prepare_request(%MyApp.LLMRequest{} = request, _opts) do
    # transform the %LLMRequest{} to what Anthropic expects...
  end

  @impl true
  defdelegate build(req, request, opts), to: ReqAI.Provider.Anthropic
end

openai = ReqAI.Provider.new(MyApp.Provider.OpenAI, model: "gpt-5.6-sol")
anthropic = ReqAI.Provider.new(MyApp.Provider.Anthropic, model: "claude-haiku-4-5")

# Swap out provider/model depending on rate limits,
# provider availability, user preferences, etc.
provider = select_provider(user, [openai, anthropic])

ReqAI.generate(provider, %MyApp.LLMRequest{
  tokens: 200,
  transcript: [{:system, "Be nice"}, {:user, "Hello"}],
})
```

`prepare_request/2` receives the same provider options as `build/3`, including the final `:stream` value selected by `generate/2` or `stream/4`. Its return value must be a provider-native map or keyword list.

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
