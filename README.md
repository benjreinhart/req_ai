# ReqAI

[![CI](https://github.com/benjreinhart/req_ai/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/benjreinhart/req_ai/actions/workflows/ci.yml)
[![Hex version](https://img.shields.io/hexpm/v/req_ai.svg)](https://hex.pm/packages/req_ai)
[![Hex Docs](https://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://req-ai.hexdocs.pm)

ReqAI is an extensible Elixir client for AI APIs, built on [Req](https://github.com/wojtekmach/req).

```elixir
{:ok, %Req.Response{}, %{"output" => [%{"content" => [content]}]}} =
  ReqAI.generate(ReqAI.Provider.OpenAI, 
    model: "gpt-5.4-mini",
    input: "Say hello"
  )

IO.puts(content["text"])
```

See the [Getting Started guide](https://req-ai.hexdocs.pm/getting-started.html) for configuration and usage examples.

## Features

- Generate and stream with one calling convention, using each provider's request and response formats.
- Built-in adapters for Anthropic, OpenAI, Gemini, xAI, OpenRouter, and TypeSafe. Add custom adapters with the [Provider](https://req-ai.hexdocs.pm/ReqAI.Provider.html) behaviour.
- Telemetry for request lifecycle, duration, token usage, and time to first chunk. Customize metadata with the [Telemetry](https://req-ai.hexdocs.pm/ReqAI.Telemetry.html) behaviour.
- Configure authentication, retries, timeouts, and testing through Req.
- Optional [translators](https://req-ai.hexdocs.pm/ReqAI.Translator.html) for your own request, response, error, and event shapes.

## Installation

Add ReqAI to your dependencies in `mix.exs`:

```elixir
{:req_ai, ">= 0.0.0"}
```

Requires Elixir 1.18 or later and Req 0.8.0 or later.
