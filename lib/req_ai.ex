defmodule ReqAI do
  alias ReqAI.Provider

  @doc """
  Generates a provider-native response.

  The configured provider builds the request with streaming disabled. Returns
  `{:ok, response}` for a successful HTTP response, `{:error, response}` for a
  non-successful HTTP response, or `{:error, exception}` when the request fails.

  The response is a `Req.Response` whose body retains the provider-native data.
  """
  @spec generate(
          provider :: Provider.t(),
          request :: term()
        ) :: {:ok, Req.Response.t()} | {:error, Req.Response.t()} | {:error, Exception.t()}
  def generate(%Provider{} = provider, request) do
    req = build_request(provider, request, false)

    case Req.request(req) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, response} ->
        {:error, response}

      {:error, _exception} = error ->
        error
    end
  end

  @doc """
  Streams a provider-native response into an accumulator.

  The provider builds the request with streaming enabled. `fun` receives each
  value decoded by Req, the response as it is being received, and the current
  accumulator. It must return `{:cont, acc}` to continue or `{:halt, acc}` to
  stop consuming the response.

  Req handles supported streaming formats such as SSE and NDJSON. The contents
  of each event remain provider-native; for example, an SSE event's JSON payload
  remains in its `:data` field.

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
          {:ok, Req.Response.t(), acc}
          | {:error, Req.Response.t(), acc}
          | {:error, Exception.t(), Req.Response.t(), acc}
        when acc: term()
  def stream(%Provider{} = provider, request, acc, fun)
      when is_function(fun, 3) do
    req = build_request(provider, request, true)

    wrapped_fun =
      fn
        event, %{status: status}, {acc, error_body} when status not in 200..299 ->
          {:cont, {acc, [event | error_body]}}

        event, response, {acc, error_body} ->
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
        {:error, put_error_body(response, error_body), acc}

      {:error, exception, response, {acc, _error_body}} ->
        {:error, exception, response, acc}
    end
  end

  defp build_request(%Provider{module: provider, req: req, opts: opts}, request, stream) do
    opts = Keyword.put(opts, :stream, stream)
    request = prepare_request(provider, request, opts)
    provider.build(req, request, opts)
  end

  defp prepare_request(provider, request, opts) do
    case Code.ensure_loaded(provider) do
      {:module, ^provider} ->
        if function_exported?(provider, :prepare_request, 2) do
          provider.prepare_request(request, opts)
        else
          request
        end

      {:error, reason} ->
        raise ArgumentError,
              "could not load provider #{inspect(provider)}: #{inspect(reason)}"
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
