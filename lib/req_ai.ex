defmodule ReqAI do
  alias ReqAI.{Provider, Telemetry}

  import ReqAI.Utils, only: [ensure_loaded!: 1, maybe_apply: 4]

  @doc """
  Generates a response.

  The configured provider builds the request with streaming disabled. The
  `Req.Response` is always returned unchanged as the second element when the
  request completes at the HTTP level. The third element is an
  application-owned value produced from that response.

  For successful responses, the third element is produced by
  `ReqAI.Translator.response/2`; for non-successful responses, it is produced
  by `ReqAI.Translator.error/2`. Both default to `response.body` when their
  callback is not implemented. Transport and decoding failures return
  `{:error, exception}` because no HTTP response or provider-native body is
  available.
  """
  @spec generate(provider :: Provider.t(), request :: term()) ::
          {:ok, Req.Response.t(), term()}
          | {:error, Req.Response.t(), term()}
          | {:error, Exception.t()}

  def generate(%Provider{module: module, opts: opts, req: req} = provider, request) do
    opts = Keyword.put(opts, :stream, false)
    request = translate_request(provider, request, opts)
    req = module.build(req, request, opts)

    Telemetry.span(
      provider.telemetry,
      provider.telemetry_metadata,
      [:req_ai, :generate],
      request,
      opts,
      fn metadata ->
        case Req.request(req) do
          {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
            metadata = put_http_metadata(metadata, response, telemetry: provider.telemetry)
            result = {:ok, response, translate_response(provider, response, opts)}
            {result, %{}, {:ok, response, metadata}}

          {:ok, response} ->
            metadata = put_http_metadata(metadata, response, telemetry: provider.telemetry)
            result = {:error, response, translate_error(provider, response, opts)}
            {result, %{}, {:ok, response, metadata}}

          {:error, exception} = error ->
            metadata = put_http_metadata(metadata, exception, telemetry: provider.telemetry)
            {error, %{}, {:error, exception, metadata}}
        end
      end
    )
  end

  @doc """
  Streams a response into an accumulator.

  The provider builds the request with streaming enabled. `fun` receives each
  provider-native event, the response as it is being received, and the current
  accumulator. It must return `{:cont, acc}` to continue or `{:halt, acc}` to
  stop consuming the response.

  Req handles transport formats such as SSE and NDJSON, then the provider
  decodes the resulting values and drops protocol-only events. For the built-in
  providers, an SSE event remains a map and its JSON payload is decoded in the
  `:data` field. When a translator implements `ReqAI.Translator.event/3`, `fun`
  receives its return value. The accompanying response remains the in-progress
  `Req.Response`.

  The completed response remains the raw `Req.Response`. For a successful
  stream, the accumulator is the application-owned result of consuming the
  translated events. For a non-successful stream, the third element is produced
  by `ReqAI.Translator.error/2`, defaulting to the buffered response body.

  Non-successful HTTP responses are not passed to `fun`. Their streamed data is
  instead collected into `response.body`; JSON error bodies are decoded when
  possible.

  Returns `{:ok, response, acc}` for a successful HTTP response,
  `{:error, response, error}` for a non-successful HTTP response, or
  `{:error, exception, response, acc}` for a transport or decoding error.
  """
  @spec stream(
          provider :: Provider.t(),
          request :: term(),
          acc,
          fun :: (term(), Req.Response.t(), acc -> {:cont, acc} | {:halt, acc})
        ) ::
          {:ok, Req.Response.t(), acc}
          | {:error, Req.Response.t(), acc}
          | {:error, Exception.t(), Req.Response.t() | nil, acc}
        when acc: term()

  def stream(%Provider{} = provider, request, acc, fun) when is_function(fun, 3) do
    opts = Keyword.put(provider.opts, :stream, true)
    request = translate_request(provider, request, opts)
    req = provider.module.build(provider.req, request, opts)

    wrapped_fun =
      fn
        event, %{status: status}, {acc, error_body, metadata, start_time, time_to_first_chunk}
        when status not in 200..299 ->
          {:cont, {acc, [event | error_body], metadata, start_time, time_to_first_chunk}}

        event, response, {acc, error_body, metadata, start_time, time_to_first_chunk} ->
          received_at = System.monotonic_time()
          events = provider.module.decode_event(event, response, opts)

          time_to_first_chunk =
            record_time_to_first_chunk(time_to_first_chunk, received_at - start_time)

          case consume_events(provider, events, response, opts, fun, acc, metadata) do
            {:cont, acc, metadata} ->
              {:cont, {acc, error_body, metadata, start_time, time_to_first_chunk}}

            {:halt, acc, metadata} ->
              {:halt, {acc, error_body, metadata, start_time, time_to_first_chunk}}
          end
      end

    Telemetry.span(
      provider.telemetry,
      Map.put(provider.telemetry_metadata, :stream, true),
      [:req_ai, :stream],
      request,
      opts,
      fn metadata ->
        start_time = System.monotonic_time()

        case Req.stream(req, {acc, [], metadata, start_time, nil}, wrapped_fun) do
          {:ok, %Req.Response{} = response, {acc, _, metadata, _start_time, time_to_first_chunk}}
          when response.status in 200..299 ->
            metadata = put_http_metadata(metadata, response, telemetry: provider.telemetry)
            measurements = stream_measurements(time_to_first_chunk)
            {{:ok, response, acc}, measurements, {:ok, response, metadata}}

          {:ok, response, {_acc, error_body, metadata, _start_time, time_to_first_chunk}} ->
            metadata = put_http_metadata(metadata, response, telemetry: provider.telemetry)
            measurements = stream_measurements(time_to_first_chunk)
            response = put_error_body(response, error_body)
            result = {:error, response, translate_error(provider, response, opts)}
            {result, measurements, {:ok, response, metadata}}

          {:error, exception, response,
           {acc, _error_body, metadata, _start_time, time_to_first_chunk}} ->
            metadata = put_http_metadata(metadata, exception, telemetry: provider.telemetry)
            measurements = stream_measurements(time_to_first_chunk)
            {{:error, exception, response, acc}, measurements, {:error, exception, metadata}}
        end
      end
    )
  end

  defp record_time_to_first_chunk(nil, elapsed), do: elapsed
  defp record_time_to_first_chunk(time_to_first_chunk, _elapsed), do: time_to_first_chunk

  defp stream_measurements(nil), do: %{}

  defp stream_measurements(time_to_first_chunk) do
    %{time_to_first_chunk: time_to_first_chunk}
  end

  defp translate_request(%Provider{translator: translator}, request, opts) do
    translator
    |> ensure_loaded!()
    |> maybe_apply(:request, [request, opts], request)
  end

  defp translate_response(%Provider{translator: translator}, response, opts) do
    maybe_apply(translator, :response, [response, opts], response.body)
  end

  defp translate_error(%Provider{translator: translator}, response, opts) do
    maybe_apply(translator, :error, [response, opts], response.body)
  end

  defp translate_event(%Provider{translator: translator}, event, response, opts) do
    maybe_apply(translator, :event, [event, response, opts], event)
  end

  defp consume_events(_provider, [], _response, _opts, _fun, acc, metadata) do
    {:cont, acc, metadata}
  end

  defp consume_events(provider, [event | events], response, opts, fun, acc, metadata) do
    metadata =
      Telemetry.event_metadata(provider.telemetry, metadata, event, response, opts)

    translated_event = translate_event(provider, event, response, opts)

    case fun.(translated_event, response, acc) do
      {:cont, acc} ->
        consume_events(provider, events, response, opts, fun, acc, metadata)

      {:halt, acc} ->
        {:halt, acc, metadata}

      other ->
        raise ArgumentError, "expected {:cont, acc} or {:halt, acc}, got: #{inspect(other)}"
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

  defp put_http_metadata(metadata, _, telemetry: false), do: metadata
  defp put_http_metadata(metadata, response, _), do: put_http_metadata(metadata, response)

  defp put_http_metadata(metadata, %Req.Response{status: status}) when status in 200..299 do
    metadata
    |> Map.put(:http_status, status)
    |> Map.put(:error, false)
  end

  defp put_http_metadata(metadata, %Req.Response{status: status}) do
    metadata
    |> Map.put(:http_status, status)
    |> Map.put(:error, true)
    |> Map.put(:error_type, Integer.to_string(status))
  end

  defp put_http_metadata(metadata, %Req.TransportError{reason: reason}) do
    reason = if is_atom(reason), do: Atom.to_string(reason), else: inspect(reason)

    metadata
    |> Map.put(:error, true)
    |> Map.put(:error_type, reason)
  end

  defp put_http_metadata(metadata, %{__struct__: module}) do
    metadata
    |> Map.put(:error, true)
    |> Map.put(:error_type, inspect(module))
  end
end
