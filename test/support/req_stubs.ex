defmodule ReqAITest.ReqStubs do
  @moduledoc false

  alias ReqAI.Provider

  def stub_provider_response_stream(provider, options) when is_list(options) do
    body = Keyword.fetch!(options, :body)
    status = Keyword.get(options, :status, 200)
    headers = Keyword.get(options, :headers, [{"content-type", "text/event-stream"}])
    stub_provider(provider, event_stream(status, headers, body))
  end

  def stub_provider_response_json(provider, options) when is_list(options) do
    body = Keyword.fetch!(options, :body)
    status = Keyword.get(options, :status, 200)
    headers = Keyword.get(options, :headers, [{"content-type", "application/json"}])
    stub_provider(provider, event_stream(status, headers, [{:data, JSON.encode!(body)}]))
  end

  def stub_provider_response_exception(provider, exception) do
    stub_provider(provider, transport_error(exception))
  end

  defp event_stream(status, headers, body) do
    test_pid = self()

    adapter = fn request, acc, fun, state ->
      send(test_pid, {:request, request})
      response = Req.Response.new(status: nil, body: nil, request: request)
      emit([{:status, status}, {:headers, headers} | body], response, acc, fun, state)
    end

    req_options(adapter)
  end

  defp transport_error(exception) do
    adapter = fn request, acc, _fun, state ->
      response = Req.Response.new(status: nil, body: nil, request: request)
      {{:error, exception}, response, acc, state}
    end

    req_options(adapter)
  end

  defp stub_provider({provider_module, provider_opts}, stub_req_options) do
    {req_options, provider_opts} = Keyword.pop(provider_opts, :req, [])
    req_options = Keyword.merge(req_options, stub_req_options)

    Provider.new(provider_module, Keyword.put(provider_opts, :req, req_options))
  end

  defp stub_provider(provider_module, stub_req_options) do
    stub_provider({provider_module, []}, stub_req_options)
  end

  defp req_options(adapter), do: [adapter: adapter, retry: false]

  defp emit([], response, acc, _fun, state) do
    {:ok, response, acc, state}
  end

  defp emit([event | events], response, acc, fun, state) do
    response = update_response(response, event)

    case fun.(event, response, acc, state) do
      {:ok, response, acc, state} -> emit(events, response, acc, fun, state)
      result -> result
    end
  end

  defp update_response(response, {:status, status}) do
    %{response | status: status}
  end

  defp update_response(response, {:headers, headers}) do
    %{response | headers: Req.Fields.new(headers)}
  end

  defp update_response(response, {:trailers, trailers}) do
    %{response | trailers: Req.Fields.new(trailers)}
  end

  defp update_response(response, {:data, _data}) do
    response
  end
end
