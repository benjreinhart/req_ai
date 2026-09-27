# Translators

Applications sometimes need interchangeable models. The same feature should work with e.g. OpenAI or Anthropic without changing the calling code. ReqAI doesn't try to unify request and response bodies across providers. A generic library can't know which differences matter to your application or how to represent them. Only your application does.

Instead, you bring your own abstraction. Configure a `ReqAI.Translator` on the provider, and ReqAI calls your callbacks at the request and response boundaries to translate between your shape and the provider's.

## A simple shared interface

Suppose an application only needs to send a prompt string and receive a text string. The provider configuration selects the model:

```elixir
{:ok, response, text} = ReqAI.generate(provider, "Explain recursion in one sentence.")
```

Implement `request/2` to turn the prompt into a provider request, and `response/2` to extract text from a successful HTTP response.

## Translate OpenAI Responses

OpenAI's [Responses API](https://developers.openai.com/api/docs/guides/text) accepts a string as `input` and returns text within its `output` items:

```elixir
defmodule MyApp.OpenAITranslator do
  @behaviour ReqAI.Translator

  @impl true
  def request(prompt, opts) when is_binary(prompt) do
    %{model: Keyword.fetch!(opts, :model), input: prompt}
  end

  @impl true
  def response(%Req.Response{body: body}, _opts) do
    [%{"content" => [%{"type" => "output_text", "text" => text}]}] = body["output"]
    text
  end
end
```

## Translate Anthropic Messages

Anthropic's [Messages API](https://platform.claude.com/docs/en/api/messages/create) takes a `messages` list and requires `max_tokens`. Its response contains a list of content blocks:

```elixir
defmodule MyApp.AnthropicTranslator do
  @behaviour ReqAI.Translator

  @impl true
  def request(prompt, opts) when is_binary(prompt) do
    %{
      model: Keyword.fetch!(opts, :model),
      max_tokens: Keyword.fetch!(opts, :max_tokens),
      messages: [%{role: "user", content: prompt}]
    }
  end

  @impl true
  def response(%Req.Response{body: body}, _opts) do
    [%{"type" => "text", "text" => text}] = body["content"]
    text
  end
end
```

## Handle success and errors

`response/2` is only invoked for successful HTTP responses, where these text-generation examples expect text content. For brevity, they assume a single text block and a single output item.

For non-2xx responses, ReqAI calls `error/2` instead. Add this callback to either translator to return the HTTP status alongside the provider's error details:

```elixir
@impl true
def error(%Req.Response{status: status, body: body}, _opts) do
  %{status: status, details: body}
end
```

For example, a 401 response returns `{:error, response, %{status: 401, details: body}}`. Without `error/2`, the third element is the original response body. Transport errors bypass this callback.

## Switch providers

Configure each provider with its translator and model. This example assumes API keys are already [configured](configuration.md):

```elixir
openai =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    translator: MyApp.OpenAITranslator,
    model: "gpt-5.4-mini"
  )

anthropic =
  ReqAI.Provider.new(ReqAI.Provider.Anthropic,
    translator: MyApp.AnthropicTranslator,
    model: "claude-sonnet-4-6",
    max_tokens: 256
  )

# For example, maybe you choose a provider based on your user's preferences.
provider = select_provider_for_user(user, [openai, anthropic])

{:ok, response, text} = ReqAI.generate(provider, "Explain recursion in one sentence.")
IO.puts(text)
```

This example is deliberately simple. Real applications may need to translate conversation history, tool calls, structured output, and provider-specific errors. Translators let you keep those differences in one place while the rest of your application uses the interface it needs.

## Translate only what you need

All translator callbacks are optional:

| Callback | Purpose | Default when omitted |
| --- | --- | --- |
| `request/2` | Convert application input to a provider request | Pass input through |
| `response/2` | Produce the third tuple element for a successful `generate/2` call | `response.body` |
| `error/2` | Produce the third tuple element for a non-2xx response | `response.body` |
| `event/3` | Convert each decoded stream event before the consumer callback | Pass the event through |

Without `error/2` or `event/3`, HTTP error bodies and streaming events keep their native formats. `response/2` is not called for streams; the consumer's accumulator is the result. Errors returned by Req bypass response and error translation, and exceptions raised by translators propagate to the caller.
