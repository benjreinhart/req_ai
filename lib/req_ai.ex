defmodule ReqAI do
  alias ReqAI.{Provider, Telemetry}

  @doc """
  Generates a response.

  The configured provider builds the request with streaming disabled. Returns
  `{:ok, response}` for a successful HTTP response, `{:error, response}` for a
  non-successful HTTP response, or `{:error, exception}` when the request fails.

  By default, the response is a `Req.Response` whose body retains the
  provider-native data. When a translator implements
  `ReqAI.Translator.response/2`, its return value is returned instead.
  """
  @spec generate(
          provider :: Provider.t(),
          request :: term()
        ) :: {:ok, term()} | {:error, term()} | {:error, Exception.t()}
  def generate(%Provider{module: module, opts: opts, req: req} = provider, request) do
    opts = Keyword.put(opts, :stream, false)
    request = translate_request(provider, request, opts)
    req = module.build(req, request, opts)

    Telemetry.span(provider, [:req_ai, :generate], request, opts, fn ->
      case Req.request(req) do
        {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
          result = {:ok, translate_response(provider, response, opts)}
          {result, {:response, response, false}}

        {:ok, response} ->
          result = {:error, translate_response(provider, response, opts)}
          {result, {:response, response, true}}

        {:error, exception} = error ->
          {error, {:error, exception}}
      end
    end)
  end

  @doc """
  Streams a response into an accumulator.

  The provider builds the request with streaming enabled. `fun` receives each
  value decoded by Req, the response as it is being received, and the current
  accumulator. It must return `{:cont, acc}` to continue or `{:halt, acc}` to
  stop consuming the response.

  Req handles supported streaming formats such as SSE and NDJSON. By default,
  the contents of each event remain provider-native; for example, an SSE
  event's JSON payload remains in its `:data` field. When a translator
  implements `ReqAI.Translator.event/3`, `fun` receives its return value. The
  accompanying response remains the in-progress `Req.Response`.

  The completed response for a successful stream remains the raw
  `Req.Response`. The accumulator is the application-owned result of consuming
  the translated events. Buffered non-successful HTTP responses are translated
  with `ReqAI.Translator.response/2` when that callback is implemented.

  Non-successful HTTP responses are not passed to `fun`. Their streamed data is
  instead collected into `response.body`; JSON error bodies are decoded when
  possible. In this case, the original accumulator is returned unchanged.

  Returns `{:ok, response, acc}` for a successful HTTP response,
  `{:error, response, acc}` for a non-successful HTTP response, or
  `{:error, exception, response, acc}` for a transport or decoding error.
  """
  @spec stream(
          provider :: Provider.t(),
          request :: term(),
          acc,
          fun :: (term(), Req.Response.t(), acc -> {:cont, acc} | {:halt, acc})
        ) ::
          {:ok, term(), acc}
          | {:error, term(), acc}
          | {:error, Exception.t(), Req.Response.t(), acc}
        when acc: term()
  def stream(%Provider{} = provider, request, acc, fun)
      when is_function(fun, 3) do
    opts = Keyword.put(provider.opts, :stream, true)
    req = build_request(provider, request, opts)

    wrapped_fun =
      fn
        event, %{status: status}, {acc, error_body} when status not in 200..299 ->
          {:cont, {acc, [event | error_body]}}

        event, response, {acc, error_body} ->
          event = translate_event(provider, event, response, opts)

          case fun.(event, response, acc) do
            {:cont, acc} ->
              {:cont, {acc, error_body}}

            {:halt, acc} ->
              {:halt, {acc, error_body}}

            other ->
              raise ArgumentError, "expected {:cont, acc} or {:halt, acc}, got: #{inspect(other)}"
          end
      end

    case Req.stream(req, {acc, []}, wrapped_fun) do
      {:ok, %Req.Response{} = response, {acc, _}} when response.status in 200..299 ->
        {:ok, response, acc}

      {:ok, response, {acc, error_body}} ->
        response = put_error_body(response, error_body)
        {:error, translate_response(provider, response, opts), acc}

      {:error, exception, response, {acc, _error_body}} ->
        {:error, exception, response, acc}
    end
  end

  defp build_request(%Provider{module: provider, req: req} = configured_provider, request, opts) do
    request = translate_request(configured_provider, request, opts)
    provider.build(req, request, opts)
  end

  defp translate_request(%Provider{translator: translator}, request, opts) do
    translate(translator, :request, [request, opts], request)
  end

  defp translate_response(%Provider{translator: translator}, response, opts) do
    translate(translator, :response, [response, opts], response)
  end

  defp translate_event(%Provider{translator: translator}, event, response, opts) do
    translate(translator, :event, [event, response, opts], event)
  end

  defp translate(nil, _callback, _args, value), do: value

  defp translate(translator, callback, args, value) do
    case Code.ensure_loaded(translator) do
      {:module, ^translator} ->
        if function_exported?(translator, callback, length(args)) do
          apply(translator, callback, args)
        else
          value
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load translator #{inspect(translator)}: #{inspect(reason)}"
    end
  end

  defp put_error_body(%Req.Response{} = response, error_body) do
    error_body =
      error_body |> Enum.reverse() |> :erlang.iolist_to_binary()

    case JSON.decode(error_body) do
      {:ok, decoded} -> %{response | body: decoded}
      {:error, _err} -> %{response | body: error_body}
    end
  end
end
