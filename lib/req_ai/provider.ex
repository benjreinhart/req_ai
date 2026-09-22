defmodule ReqAI.Provider do
  @moduledoc """
  Defines the adapter contract and represents a configured AI provider.

  Providers build the `Req.Request` used to execute provider-native request
  data. An optional `ReqAI.Translator` can translate application values at the
  provider boundary.

  ## Custom providers

  Implement `c:build/3` to support generation. For example, an application-owned
  JSON endpoint can use the same calling convention as the built-in providers:

      defmodule MyApp.Provider do
        @behaviour ReqAI.Provider

        @impl true
        def build(req, request, _opts) do
          Req.merge(req,
            method: :post,
            url: "https://llm.example.com/generate",
            json: request
          )
        end
      end

      provider = ReqAI.Provider.new(MyApp.Provider)
      ReqAI.generate(provider, %{prompt: "Say hello"})

  To support streaming, also implement `c:decode_event/3` and use `opts[:stream]`
  in `c:build/3` to select the endpoint's streaming mode. The decoder returns a
  list of events; returning `[]` drops an event. Req handles transport framing
  such as SSE, while the provider decodes the native payload.
  """

  @doc """
  Builds the HTTP request for a provider-native request body.
  """
  @callback build(
              req :: Req.Request.t(),
              request :: map() | keyword(),
              opts :: keyword()
            ) :: Req.Request.t()

  @doc """
  Decodes a raw stream event produced by Req (an SSE event map, an NDJSON
  line, ...) into zero or more application events.

  This callback is optional. Providers must implement it to support `ReqAI.stream/4`.
  """
  @callback decode_event(
              event :: term(),
              response :: Req.Response.t(),
              opts :: keyword()
            ) :: [term()]

  @optional_callbacks decode_event: 3

  @enforce_keys [:module, :req, :opts]
  defstruct [:module, :req, :opts, :translator, :telemetry, telemetry_metadata: %{}]

  @type t :: %__MODULE__{
          module: module(),
          req: Req.Request.t(),
          opts: keyword(),
          translator: module() | nil,
          telemetry: module() | false,
          telemetry_metadata: map()
        }

  @doc """
  Creates a configured provider using `module` as its adapter.

  `module` must implement the `ReqAI.Provider` behaviour.

  The `:req` option contains options passed to `Req.new/2`. These are
  merged with any `:req` options configured for the adapter under
  `config :req_ai, :providers`, with explicit options taking precedence.
  Configuration is read when the provider is created. Only `:req` is read from
  application configuration; extension options must be passed here directly.
  After extracting `:req`, `:translator`, `:telemetry`, and
  `:telemetry_metadata`, remaining options are stored on the provider and
  passed to `c:build/3` and the configured translator callbacks for each request.

  Built-in adapters take body parameters, including `:model`, from the request
  passed to `ReqAI.generate/2` or `ReqAI.stream/4`. They do not merge provider
  options into that body. Configure authentication through `:req`, using Req's
  `:auth` or `:headers` options as appropriate for the provider.

  The optional `:translator` must implement the `ReqAI.Translator` behaviour.

  The `:telemetry` option selects a module implementing any of the optional
  `ReqAI.Telemetry` callbacks and defaults to the provider module. Set it to
  `false` to disable telemetry emission. The `:telemetry_metadata` option
  accepts a map that is passed to the telemetry callbacks.
  """
  @spec new(module :: module(), opts :: keyword()) :: t()
  def new(module, opts \\ []) do
    {req_opts, opts} = Keyword.pop(opts, :req, [])
    {translator, opts} = Keyword.pop(opts, :translator, nil)
    {telemetry, opts} = Keyword.pop(opts, :telemetry, module)
    {telemetry_metadata, opts} = Keyword.pop(opts, :telemetry_metadata, %{})

    req =
      module
      |> application_config()
      |> Keyword.get(:req, [])
      |> Req.new(req_opts)

    %__MODULE__{
      module: module,
      req: req,
      opts: opts,
      translator: translator,
      telemetry: telemetry,
      telemetry_metadata: telemetry_metadata
    }
  end

  defp application_config(provider) do
    :req_ai |> Application.get_env(:providers, []) |> Keyword.get(provider, [])
  end
end
