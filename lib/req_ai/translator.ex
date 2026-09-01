defmodule ReqAI.Translator do
  @moduledoc """
  Defines translations between application values and provider-native values.

  A translator is configured on a `ReqAI.Provider` and may implement any of the
  callbacks in this behaviour. Values are left unchanged when the corresponding
  callback is not implemented.

  Translators let applications own shared request, response, and event
  representations without requiring ReqAI or its provider adapters to define a
  universal representation.
  """

  @doc """
  Translates application input into a provider-native request body.

  `opts` contains the configured provider options and the final `:stream` value
  for the current call.
  """
  @callback request(request :: term(), opts :: keyword()) :: map() | keyword()

  @doc """
  Translates a buffered HTTP response into an application response.

  This callback is invoked for successful and non-successful responses from
  `ReqAI.generate/2`, and for buffered non-successful HTTP responses from
  `ReqAI.stream/4`.

  It is not invoked for successful streams, where the accumulator is the
  application-owned result and the returned `Req.Response` retains transport
  metadata. It is also not invoked for transport errors.
  """
  @callback response(response :: Req.Response.t(), opts :: keyword()) :: term()

  @doc """
  Translates a provider-native streamed event into an application event.

  `response` is the HTTP response as it is being received.
  """
  @callback event(event :: term(), response :: Req.Response.t(), opts :: keyword()) :: term()

  @optional_callbacks request: 2, response: 2, event: 3
end
