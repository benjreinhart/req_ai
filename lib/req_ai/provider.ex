defmodule ReqAI.Provider do
  @moduledoc """
  Defines the adapter contract and represents a configured AI provider.

  Providers build the `Req.Request` used to execute provider-native request
  data. An optional `ReqAI.Translator` can translate application values at the
  provider boundary.
  """

  @doc """
  Builds the HTTP request for a provider-native request body.
  """
  @callback build(
              req :: Req.Request.t(),
              request :: map() | keyword(),
              opts :: keyword()
            ) :: Req.Request.t()

  @callback telemetry(
              source :: {:request, map() | keyword()} | {:response, Req.Response.t()},
              opts :: keyword()
            ) :: map()

  @enforce_keys [:module, :req, :opts]
  defstruct [:module, :req, :opts, :translator]

  @type t :: %__MODULE__{
          module: module(),
          req: Req.Request.t(),
          opts: keyword(),
          translator: module() | nil
        }

  @doc """
  Creates a configured provider using `module` as its adapter.

  `module` must implement the `ReqAI.Provider` behaviour.

  The `:req` option contains options passed to `Req.new/2`. These are
  merged with any `:req` options configured for the adapter under
  `config :req_ai, :providers`. All remaining options are stored on the
  provider and passed to `build/3` and the configured translator callbacks for
  each request.

  The optional `:translator` must implement the `ReqAI.Translator` behaviour.
  """
  @spec new(module :: module(), opts :: keyword()) :: t()
  def new(module, opts) do
    {req_opts, opts} = Keyword.pop(opts, :req, [])
    {translator, opts} = Keyword.pop(opts, :translator, nil)

    req =
      module
      |> application_config()
      |> Keyword.get(:req, [])
      |> Req.new(req_opts)

    %__MODULE__{module: module, req: req, opts: opts, translator: translator}
  end

  defp application_config(provider) do
    :req_ai |> Application.get_env(:providers, []) |> Keyword.get(provider, [])
  end
end
