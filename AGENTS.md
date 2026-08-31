# ReqAI project context

ReqAI is a lightweight Elixir wrapper for LLM providers. It aims to give agent systems a consistent interface across providers and models while preserving access to provider-native request parameters, response bodies, and streamed events.

## Design goals

- The high-level API is still a work in progress.
- Keep requests, responses, and streamed events provider-native by default. Callers must be able to pass provider-specific body parameters and access raw provider data.
- Let applications and higher-level libraries own any consolidated request or response representations. ReqAI should provide composition points for translating those representations at the provider boundary without defining a universal schema itself.
- Standardize execution and control flow without pretending every provider is identical.
- Treat telemetry and observability as foundational. The common boundary should make model calls easy to monitor without exposing secrets or unnecessarily recording sensitive content.
- Keep the library focused and lightweight: provide strong primitives and well-maintained adapters for a handful of popular APIs instead of an exhaustive model catalog.
- Make new providers and application-defined adapter layers straightforward to add through a clear, composable adapter contract.
- Prefer simple interfaces and values. Avoid too many custom structs or behaviours. We want adoption to be quick, easy, and readable.
- Preserve forward compatibility. Avoid dropping unknown provider fields or forcing lossy conversions as APIs evolve.

## Current state

The current API is lower-level than the intended interface: callers construct clients through modules under `ReqAI.Provider`, and request/response data remains provider-native. OpenAI, Anthropic, Gemini, xAI, and OpenRouter adapters are present. Do not document planned standardized behavior as already implemented.

Run `mix format --check-formatted` and `mix test` before handing off changes.
