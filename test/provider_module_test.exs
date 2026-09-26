defmodule ReqAI.ProviderModuleTest do
  use ExUnit.Case, async: false

  alias ReqAI.Provider.OpenAI
  alias ReqAITest.ReqStubs

  defmodule NonStreamingProvider do
    @behaviour ReqAI.Provider

    @impl true
    def build(req, request, opts) do
      send(self(), :provider_build)
      OpenAI.build(req, request, opts)
    end
  end

  setup do
    previous = Application.fetch_env(:req_ai, :providers)

    on_exit(fn ->
      case previous do
        {:ok, providers} -> Application.put_env(:req_ai, :providers, providers)
        :error -> Application.delete_env(:req_ai, :providers)
      end
    end)

    :ok
  end

  test "generate accepts a module, reads current HTTP configuration, and emits provider telemetry" do
    stub = ReqStubs.stub_provider_response_json(OpenAI, body: %{"model" => "test-model"})

    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      [:req_ai, :generate, :stop],
      &__MODULE__.handle_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    for value <- ["first", "second"] do
      configure(stub, value)

      assert {:ok, %Req.Response{status: 200}, %{"model" => "test-model"}} =
               ReqAI.generate(OpenAI, model: "test-model", input: "Hello", stream: true)

      assert_receive {:request, request}
      assert Req.Request.get_header(request, "x-config") == [value]
      assert JSON.decode!(IO.iodata_to_binary(request.body))["stream"] == false
      assert_receive {:telemetry, %{provider: "openai", model: "test-model"}}
    end
  end

  test "stream accepts a module and decodes events using configured HTTP options" do
    stub =
      ReqStubs.stub_provider_response_stream(OpenAI,
        body: [{:data, "event: response.output_text.delta\ndata: {\"delta\":\"Hello\"}\n\n"}]
      )

    configure(stub, "stream")

    assert {:ok, %Req.Response{status: 200}, [%{data: %{"delta" => "Hello"}}]} =
             ReqAI.stream(OpenAI, %{model: "test-model", input: "Hello", stream: false}, [], fn
               event, _response, events -> {:cont, [event | events]}
             end)

    assert_receive {:request, request}
    assert Req.Request.get_header(request, "x-config") == ["stream"]
    assert JSON.decode!(IO.iodata_to_binary(request.body))["stream"] == true
  end

  test "custom modules support generation and retain the unsupported streaming error" do
    stub = ReqStubs.stub_provider_response_json(NonStreamingProvider, body: %{"ok" => true})
    configure(stub, "custom")

    assert {:ok, %Req.Response{status: 200}, %{"ok" => true}} =
             ReqAI.generate(NonStreamingProvider, %{input: "Hello"})

    assert_receive :provider_build

    assert_raise ArgumentError, ~r/does not support streaming: decode_event\/3/, fn ->
      ReqAI.stream(NonStreamingProvider, %{}, [], fn _, _, acc -> {:cont, acc} end)
    end

    refute_received :provider_build
  end

  def handle_telemetry(_event, _measurements, metadata, pid) do
    send(pid, {:telemetry, metadata})
  end

  defp configure(stub, value) do
    Application.put_env(:req_ai, :providers, [
      {stub.module,
       req: [
         adapter: stub.req.adapter,
         retry: false,
         headers: [{"x-config", value}]
       ]}
    ])
  end
end
