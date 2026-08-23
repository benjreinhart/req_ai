# ReqAI project context

ReqAI is a lightweight Elixir wrapper for LLM providers. It aims to give agent systems a consistent interface across providers and models while preserving access to provider-native request parameters, response bodies, and streamed events.

## Design direction

- The high-level API is still a work in progress.
- Standardize the common path without pretending every provider is identical. Callers must be able to pass provider-specific body parameters and access raw provider data.
- Treat telemetry and observability as foundational. The common boundary should make model calls easy to monitor without exposing secrets or unnecessarily recording sensitive content.
- Keep the library focused and lightweight: provide strong primitives and well-maintained adapters for a handful of popular APIs instead of an exhaustive model catalog.
- Make new providers straightforward to add through a clear adapter contract.
- Prefer simple interfaces and values. Avoid too many custom structs or behaviours. We want adoption to be quick, easy, and readable.
- Preserve forward compatibility. Avoid dropping unknown provider fields or forcing lossy conversions as APIs evolve.

## Current state

The current API is lower-level than the intended interface: callers construct clients through modules under `ReqAI.Providers`, and request/response data remains provider-native. OpenAI, Anthropic, Gemini, xAI, and OpenRouter adapters are present. Do not document planned standardized behavior as already implemented.

Run `mix format --check-formatted` and `mix test` before handing off changes.
