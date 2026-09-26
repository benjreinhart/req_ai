# ReqAI

[![CI](https://github.com/benjreinhart/req_ai/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/benjreinhart/req_ai/actions/workflows/ci.yml)
[![Hex version](https://img.shields.io/hexpm/v/req_ai.svg)](https://hex.pm/packages/req_ai)
[![Hex Docs](https://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://req-ai.hexdocs.pm)

ReqAI is a lightweight Elixir client for LLM APIs, built on [Req](https://github.com/wojtekmach/req).

```elixir
alias ReqAI.Provider.OpenAI

{:ok, %Req.Response{}, body} =
  ReqAI.generate(OpenAI, model: "gpt-5.4-mini", input: "Say hello")

%{"output" => [%{"content" => [%{"text" => text}]}]} = body

IO.puts(text)
```

See the [Getting Started guide](https://req-ai.hexdocs.pm/getting-started.html) for configuration and usage examples.

## Philosophy

- **Preserve provider-native formats.** Use the request and response formats defined by each provider’s API so your code maps directly to its documentation and examples.
- **Keep the core small.** Focus on a few powerful abstractions and a handful of popular providers.
- **Make extension easy.** Support custom providers, telemetry, and request and response body transformations so applications can bring their own conventions.
- **Treat observability as a first-class feature.** Include useful telemetry for common events and make it easy to add application-specific instrumentation.

## Features

- Generate and stream with one calling convention across providers
- Adapters for Anthropic, OpenAI, Gemini, xAI, and OpenRouter. BYO using the [Provider](https://req-ai.hexdocs.pm/ReqAI.Provider.html) behaviour
- Telemetry for lifecycle, duration, token usage, time to first chunk, etc. BYO using the [Telemetry](https://req-ai.hexdocs.pm/ReqAI.Telemetry.html) behaviour
- Full control of the underlying Req client: auth, retries, timeouts, testing
- Optional [translators](https://req-ai.hexdocs.pm/ReqAI.Translator.html) for your own request, response, error, and event shapes

## Installation

Add ReqAI to your dependencies in `mix.exs`:

```elixir
{:req_ai, ">= 0.0.0"}
```

Requires Elixir 1.18 or later and Req 0.8.0 or later.
