defmodule ReqAI.Translator do
  @moduledoc """
  Defines translations between application values and provider-native values.

  A translator is configured on a `ReqAI.Provider` and may implement any of the
  callbacks in this behaviour. Requests and events are left unchanged when the
  corresponding callback is not implemented. Response and error values default
  to the provider-native `Req.Response.body`.

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
  Translates a successful HTTP response into an application response.

  This callback produces the third element returned by `ReqAI.generate/2` for
  a successful response. It is not invoked for streams or transport errors.
  """
  @callback response(response :: Req.Response.t(), opts :: keyword()) :: term()

  @doc """
  Translates a non-successful HTTP response into an application error.

  This callback produces the third element returned by `ReqAI.generate/2` or
  `ReqAI.stream/4` for a non-successful response. For streams, `response.body`
  contains the buffered and, when possible, JSON-decoded error body. It is not
  invoked for transport or decoding errors. Its return is an application value;
  ReqAI does not reinterpret or raise it.
  """
  @callback error(response :: Req.Response.t(), opts :: keyword()) :: term()

  @doc """
  Translates a provider-native streamed event into an application event.

  `response` is the HTTP response as it is being received.
  """
  @callback event(event :: term(), response :: Req.Response.t(), opts :: keyword()) :: term()

  @optional_callbacks request: 2, response: 2, error: 2, event: 3
end
