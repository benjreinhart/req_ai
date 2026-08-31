defmodule ReqAI.Provider do
  @moduledoc """
  Defines the adapter contract and represents a configured AI provider.

  Providers can prepare application input into a provider-native request before
  building the `Req.Request` used to execute it.
  """

  @doc """
  Transforms caller input into a provider-native request body.

  `opts` contains the configured provider options and the final `:stream` value
  for the current call. The returned request is passed to `build/3`.
  """
  @callback prepare_request(request :: term(), opts :: keyword()) :: map() | keyword()

  @optional_callbacks prepare_request: 2

  @doc """
  Builds the HTTP request for a provider-native request body.
  """
  @callback build(req :: Req.Request.t(), request :: map() | keyword(), opts :: keyword()) ::
              Req.Request.t()

  @enforce_keys [:module, :req, :opts]
  defstruct [:module, :req, :opts]

  @type t :: %__MODULE__{
          module: module(),
          req: Req.Request.t(),
          opts: keyword()
        }

  @doc """
  Creates a configured provider using `module` as its adapter.

  `module` must implement the `ReqAI.Provider` behaviour.

  The `:req` option contains options passed to `Req.new/2`. These are
  merged with any `:req` options configured for the adapter under
  `config :req_ai, :providers`. All remaining options are stored on the
  provider and passed to `build/3` and `prepare_request/2` for each request.
  """
  @spec new(module :: module(), opts :: keyword()) :: t()
  def new(module, opts) do
    {req_opts, opts} = Keyword.pop(opts, :req, [])

    req =
      module
      |> application_config()
      |> Keyword.get(:req, [])
      |> Req.new(req_opts)

    %__MODULE__{module: module, req: req, opts: opts}
  end

  defp application_config(provider) do
    :req_ai |> Application.get_env(:providers, []) |> Keyword.get(provider, [])
  end
end
