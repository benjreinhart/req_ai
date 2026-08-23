defmodule ReqAITest do
  use ExUnit.Case, async: true

  alias ReqAI.Provider.OpenAI
  alias ReqAITest.ReqStubs

  @request %{model: "gpt-5.4", input: "Say hello."}

  describe "stream/4" do
    test "builds a streaming request and emits decoded SSE events" do
      provider =
        ReqStubs.stub_provider_response_stream(
          {OpenAI, [stream: false]},
          body: [
            {:data,
             ~s(event: response.output_text.delta\ndata: {"type":"response.output_text.delta",)},
            {:data, ~s("delta":"Hello!"}\n\n)},
            {:data,
             ~s(event: response.completed\ndata: {"type":"response.completed","response":{"id":"resp_123","status":"completed"}}\n\n)}
          ]
        )

      assert {:ok, response, events} =
               ReqAI.stream(provider, Map.put(@request, :stream, false), [], fn
                 event, response, events ->
                   assert response.status == 200
                   {:cont, events ++ [event]}
               end)

      assert response.status == 200
      assert Req.Response.get_header(response, "content-type") == ["text/event-stream"]

      assert Enum.map(events, & &1.data) == [
               ~s({"type":"response.output_text.delta","delta":"Hello!"}),
               ~s({"type":"response.completed","response":{"id":"resp_123","status":"completed"}})
             ]

      assert_receive {:request, request}

      assert request.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "input" => "Say hello.",
               "model" => "gpt-5.4",
               "stream" => true
             }
    end

    test "stream allows the callback to halt consumption" do
      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          headers: [{"content-type", "application/octet-stream"}],
          body: [{:data, "first"}, {:data, "second"}]
        )

      assert {:ok, response, ["first"]} =
               ReqAI.stream(provider, @request, [], fn chunk, _response, chunks ->
                 {:halt, [chunk | chunks]}
               end)

      assert response.status == 200
    end

    test "stream buffers JSON error responses without invoking the callback" do
      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          status: 401,
          headers: [{"content-type", "application/json"}],
          body: [
            {:data, ~s({"error":{"message":)},
            {:data, ~s("Invalid API key.","type":"invalid_request_error"}})}
          ]
        )

      assert {:error, response, :initial} =
               ReqAI.stream(provider, @request, :initial, fn _chunk, _response, _acc ->
                 flunk("callback should not be invoked for a non-2xx response")
               end)

      assert response.status == 401

      assert response.body == %{
               "error" => %{
                 "message" => "Invalid API key.",
                 "type" => "invalid_request_error"
               }
             }
    end

    test "stream buffers plain-text error responses" do
      provider =
        ReqStubs.stub_provider_response_stream(OpenAI,
          status: 429,
          headers: [{"content-type", "text/plain"}],
          body: [{:data, "rate "}, {:data, "limited"}]
        )

      assert {:error, response, []} =
               ReqAI.stream(provider, @request, [], fn _chunk, _response, _acc ->
                 flunk("callback should not be invoked for a non-2xx response")
               end)

      assert response.status == 429
      assert response.body == "rate limited"
    end

    test "preserves transport errors and the accumulator" do
      exception = %Req.TransportError{reason: :timeout}
      provider = ReqStubs.stub_provider_response_exception(OpenAI, exception)

      assert {:error, ^exception, response, :initial} =
               ReqAI.stream(provider, @request, :initial, fn _chunk, _response, acc ->
                 {:cont, acc}
               end)

      assert response.status == nil
    end
  end

  describe "generate/2" do
    test "returns a successful response" do
      response_body = %{
        "id" => "resp_123",
        "object" => "response",
        "status" => "completed",
        "model" => "gpt-5.4",
        "output" => []
      }

      provider =
        ReqStubs.stub_provider_response_json(OpenAI, body: response_body)

      assert {:ok, response} = ReqAI.generate(provider, Map.put(@request, :stream, true))
      assert response.status == 200
      assert response.body == response_body

      assert_receive {:request, request}

      assert request.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "input" => "Say hello.",
               "model" => "gpt-5.4",
               "stream" => false
             }
    end

    test "returns a non-successful response as an error" do
      error_body = %{
        "error" => %{
          "message" => "Invalid request.",
          "type" => "invalid_request_error"
        }
      }

      provider =
        ReqStubs.stub_provider_response_json(OpenAI,
          status: 400,
          body: error_body
        )

      assert {:error, response} = ReqAI.generate(provider, @request)
      assert response.status == 400
      assert response.body == error_body
    end

    test "returns request exceptions" do
      exception = %Req.TransportError{reason: :timeout}

      provider = ReqStubs.stub_provider_response_exception(OpenAI, exception)

      assert {:error, ^exception} = ReqAI.generate(provider, @request)
    end
  end
end
