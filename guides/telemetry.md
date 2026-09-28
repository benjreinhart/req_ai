# Telemetry

ReqAI emits telemetry by default. Anthropic, OpenAI, Gemini, and OpenRouter use the same event names and add metadata from their native requests and responses.

## Default events

`ReqAI.generate/2` uses the prefix `[:req_ai, :generate]`; `ReqAI.stream/4` uses `[:req_ai, :stream]`.

| Event suffix | When emitted | Measurements |
| --- | --- | --- |
| `:start` | Before the HTTP request | `:system_time`, `:monotonic_time` |
| `:stop` | When the call returns, including HTTP and transport errors or an early stream halt | `:duration`, `:monotonic_time`; streams also include `:time_to_first_chunk` when available |
| `:exception` | When code inside the telemetry span raises, throws, or exits | `:duration`, `:monotonic_time` |

For example, a completed generation emits `[:req_ai, :generate, :stop]`. Attach handlers with `:telemetry.attach/4` or `:telemetry.attach_many/4` to consume these events. There is no separate telemetry event for each streamed chunk.

Time measurements use native units. Convert a duration to milliseconds with `System.convert_time_unit(duration, :native, :millisecond)`. Time to first chunk measures the first Req stream callback for a 2xx response, even if the provider discards that event as protocol-only.

Request translation and request construction happen before the span, so failures there do not emit these events. Exception metadata includes `:kind`, `:reason`, and `:stacktrace`.

### Default metadata

Start metadata includes the requested `:model`, when supplied, and these provider attributes:

| Adapter | `:provider` | `:operation` |
| --- | --- | --- |
| Anthropic | `"anthropic"` | `"chat"` |
| OpenAI | `"openai"` | `"chat"` |
| Gemini | `"gcp.gemini"` | `"generate_content"` |
| OpenRouter | `"openrouter"` | `"chat"` |
| TypeSafe (Jev) | `"typesafe"` | `"evaluate"` |

Streaming calls also include `stream: true`.

Stop metadata retains the start attributes and adds:

- `:http_status_code` for completed HTTP responses, `:error`, and `:error_type` on errors. These describe the HTTP or transport outcome; a provider can report a failure inside a 2xx response while `:error` is `false`.
- `:response_id`, `:response_model`, `:input_tokens`, `:output_tokens`, `:cache_read_input_tokens`, `:cache_write_input_tokens`, `:reasoning_output_tokens`, and `:finish_reasons` when available. Finish reasons are a list of provider-specific stop reasons or terminal statuses.

For streams, response attributes accumulate from decoded events. Halting before usage arrives leaves token counts unavailable. Built-in extractors do not record request or response bodies.

TypeSafe supports generation only. Its extractor records the response model and reported input/output token usage, but no finish reasons. State, questions, answers, probabilities, and confidence remain in the native request/response bodies and are not recorded in telemetry.

### Response IDs and token counts

These fields are metadata in both generation and streaming events:

- `:response_id` is the provider's message, response, completion, or interaction ID, not an HTTP request ID.
- `:input_tokens` includes cache reads and cache writes. `:cache_read_input_tokens` counts input tokens served from cache; `:cache_write_input_tokens` counts input tokens written to cache.
- `:output_tokens` includes reasoning/thinking tokens. `:reasoning_output_tokens` is the separately reported reasoning/thinking portion.

Breakdowns are subsets of the totals: do not add them to the totals again. Anthropic's input total is normalized by adding its cache read and cache creation counts to its uncached input count. Gemini's output total adds its separately reported thought tokens. Other adapters retain the provider's inclusive totals.

| Adapter | Response ID | Cache reads | Cache writes | Reasoning output |
| --- | --- | --- | --- | --- |
| Anthropic | Yes | Yes | Yes | — |
| OpenAI | Yes | Yes | Yes | Yes |
| Gemini | Yes | Yes | — | Yes |
| OpenRouter | Yes | Yes | Yes | Yes |
| TypeSafe | — | — | — | — |

Fields are emitted only when reported; unsupported, missing, or null breakdowns are omitted, while reported zeros are preserved. Streaming usage snapshots replace earlier counts rather than being summed. Availability can depend on the model and how much of a stream was consumed.

## Add custom attributes

Pass `:telemetry_metadata` when constructing a provider to correlate calls with an application request or conversation.

```elixir
provider =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    telemetry_metadata: %{
      conversation_id: "conversation_123",
      request_id: "request_456"
    }
  )

ReqAI.generate(provider, model: "gpt-5.4-mini", input: "Summarize this text: ...")
```

The metadata initializes each call's telemetry and is passed to the extraction callbacks. Use distinct keys for custom attributes; extractors can overwrite existing keys.

## Implement custom extraction

Implement `ReqAI.Telemetry` to derive attributes from requests, responses, or streamed events. All callbacks are optional:

| Callback | Input and timing |
| --- | --- |
| `request_metadata/3` | The translated request, before `:start` |
| `response_metadata/3` | A completed non-streaming response, including non-2xx responses; never called for streams or returned transport errors |
| `event_metadata/4` | Each decoded provider event, before event translation and the consumer callback |

Each callback receives the current metadata and returns its replacement. Update that map to preserve earlier attributes. Options contain the provider's extra options and the call's `:stream` flag.

A custom module replaces the provider's extractor. Delegate to the provider to retain its default attributes. This OpenAI example adds the provider's HTTP request ID and counts decoded stream events:

```elixir
defmodule MyApp.OpenAITelemetry do
  @behaviour ReqAI.Telemetry

  alias ReqAI.Provider.OpenAI

  @impl true
  def request_metadata(metadata, request, opts) do
    OpenAI.request_metadata(metadata, request, opts)
  end

  @impl true
  def response_metadata(metadata, response, opts) do
    metadata = OpenAI.response_metadata(metadata, response, opts)

    case Req.Response.get_header(response, "x-request-id") do
      [id | _] -> Map.put(metadata, :provider_request_id, id)
      [] -> metadata
    end
  end

  @impl true
  def event_metadata(metadata, event, response, opts) do
    metadata
    |> OpenAI.event_metadata(event, response, opts)
    |> Map.update(:event_count, 1, &(&1 + 1))
  end
end

provider =
  ReqAI.Provider.new(ReqAI.Provider.OpenAI,
    telemetry: MyApp.OpenAITelemetry,
    telemetry_metadata: %{feature: :summarizer}
  )
```

The provider request ID is added to generation stop metadata; the event count is added to streaming stop metadata. Custom extraction changes metadata, not event names or measurements.

## Disabling telemetry

Set `telemetry: false` on the provider to disable both extraction and event emission.

```elixir
provider = ReqAI.Provider.new(ReqAI.Provider.OpenAI, telemetry: false)
```
