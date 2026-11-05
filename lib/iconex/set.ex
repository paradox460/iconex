defmodule Iconex.Set do
  @moduledoc """
  The behaviour every icon set implements, and the registry of known sets.

  Each set is identified by an atom (`:lucide`, ...) that names its component
  function (`Iconex.lucide/1`), its config key (`config :iconex, lucide: [...]`),
  its data file (`priv/sets/lucide.json`) and its sprite symbol prefix
  (`#lucide-house`).

  ## Data files

  `mix iconex.download SET` fetches a set's upstream data and writes it in a
  normalized form shared by every set:

      {"set": "lucide", "version": "1.47.0",
       "icons": {"house": {"viewBox": "0 0 24 24",
                           "nodes": [["path", {"d": "..."}], ...]}}}

  Nodes are `[tag, attrs]` or `[tag, attrs, children]` with string attribute
  values.

  ## Adding an icon set

    1. Write `Iconex.Set.<Name>` implementing this behaviour.
    2. Register it in `modules/0`.
    3. Add a component function named after the id in `Iconex`, wrapped in
       `if :<id> in @sets do ... end`.
    4. Add its pinned version to `@set_versions` in `mix.exs` and its data file
       to `package[:files]`.
    5. Add its license text under `licenses/`.
  """

  @typedoc "`%{\"viewBox\" => String.t(), \"nodes\" => [node]}`"
  @type icon :: %{required(String.t()) => term()}

  @doc "The npm package the set's data is downloaded from."
  @callback npm_package() :: String.t()

  @doc "The URL of the upstream data for `version`."
  @callback data_url(version :: String.t()) :: String.t()

  @doc "Converts the decoded upstream data to `%{name => icon}`."
  @callback normalize(decoded :: term()) :: {:ok, %{String.t() => icon()}} | :error

  @doc "Presentation attributes placed on every `<symbol>` of the set."
  @callback symbol_attrs() :: [{String.t(), String.t()}]

  @doc "Where users can look up the set's icon names."
  @callback docs_url() :: String.t()

  @doc "Known sets, keyed by id."
  def modules, do: [lucide: Iconex.Set.Lucide]

  @doc "Known set ids."
  def ids, do: Keyword.keys(modules())

  @doc "The module implementing set `id`."
  def module!(id), do: Keyword.fetch!(modules(), id)

  @doc "Reads a normalized data file written by `mix iconex.download`."
  @spec read(Path.t()) :: {:ok, %{String.t() => icon()}} | :error
  def read(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{"icons" => %{} = icons}} <- JSON.decode(body) do
      {:ok, icons}
    else
      _ -> :error
    end
  end
end
