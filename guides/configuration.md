# Provider configuration

`ReqAI.Provider.new/2` accepts a provider module and options. HTTP configuration goes under `:req`: authentication, headers, timeouts, retries, and other options supported by `Req.new/2`.

You can set application defaults, supply options when creating a provider, or combine the two.

## Application configuration

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

## Configure a provider directly

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

## Override request configuration

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

## HTTP options and body parameters

Put HTTP options under `:req` when creating the provider. Put model names and other API body parameters in the request passed to `ReqAI.generate/2` or `ReqAI.stream/4`.

Arbitrary options can be passed to `ReqAI.Provider.new/2`. These will later be passed to the provider, telemetry, and translator modules when their callbacks are invoked. This enables clients to supply runtime configuration when desired.