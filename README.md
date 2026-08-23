# ReqAI

ReqAI is a lightweight Elixir runtime for provider-native LLM APIs. It provides a common execution boundary for model calls without imposing a universal request and response model.

## Why ReqAI?

LLM APIs differ in important ways and evolve too quickly for a complete universal data model. ReqAI is designed to give applications one place for generation, streaming, monitoring, testing, policy, and extension without forcing inherently different APIs into lossy shared request and response types.

The current API is intentionally lower-level: callers configure adapters under `ReqAI.Provider` and pass provider-native request data. Applications can add their own unified representation at the layer where their requirements and supported providers are known.

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
