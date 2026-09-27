defmodule ReqAI.Provider.TypeSafeTest do
  use ExUnit.Case, async: true

  alias ReqAI.Provider.TypeSafe
  alias ReqAITest.ReqStubs

  @request %{
    model: "jev-latest",
    state: "Please cancel my subscription.",
    questions: %{cancel: %{type: "noul", instructions: "Is cancellation requested?"}}
  }
  @response %{
    "model" => "jev-1.13.0",
    "answers" => %{"cancel" => %{"type" => "noul", "noul" => 0.95}},
    "usage" => %{"input_tokens" => 120, "output_tokens" => 0}
  }

  test "posts native requests with bearer auth and preserves structured answers" do
    provider =
      ReqStubs.stub_provider_response_json(
        {TypeSafe, req: [auth: {:bearer, "test-key"}]},
        body: @response
      )

    for body <- [@request, Map.to_list(@request)] do
      assert {:ok, _, @response} = ReqAI.generate(provider, body)
      assert_receive {:request, request}
      assert request.method == :post
      assert URI.to_string(request.url) == "https://api.typesafe.ai/v1/systemone"
      assert Req.Request.get_header(request, "authorization") == ["Bearer test-key"]

      assert JSON.decode!(IO.iodata_to_binary(request.body)) ==
               JSON.decode!(JSON.encode!(@request))
    end
  end

  test "rejects streaming before sending a request" do
    provider = ReqStubs.stub_provider_response_json(TypeSafe, body: @response)

    assert_raise ArgumentError, ~r/TypeSafe does not support streaming/, fn ->
      ReqAI.stream(provider, @request, [], fn _, _, acc -> {:cont, acc} end)
    end

    refute_received {:request, _}
  end

  test "extracts evaluation metadata and usage without recording answers or finish reasons" do
    metadata = TypeSafe.request_metadata(%{feature: :routing}, @request, [])

    assert metadata == %{
             feature: :routing,
             operation: "evaluate",
             provider: "typesafe",
             model: "jev-latest"
           }

    response = Req.Response.new(status: 200, body: @response)

    assert TypeSafe.response_metadata(metadata, response, []) ==
             Map.merge(metadata, %{
               response_model: "jev-1.13.0",
               input_tokens: 120,
               output_tokens: 0
             })

    for response <- [
          Req.Response.new(status: 200, body: %{}),
          Req.Response.new(status: 422, body: %{"detail" => "Invalid question"})
        ] do
      assert TypeSafe.response_metadata(metadata, response, []) == metadata
    end
  end
end
