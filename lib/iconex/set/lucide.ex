defmodule Iconex.Set.Lucide do
  @moduledoc """
  [Lucide](https://lucide.dev) icons, from the `lucide-static` npm package's
  `icon-nodes.json`. Stroke-based, on a 24-unit grid.
  """

  @behaviour Iconex.Set

  @impl true
  def npm_package, do: "lucide-static"

  @impl true
  def data_url(version),
    do: "https://cdn.jsdelivr.net/npm/lucide-static@#{version}/icon-nodes.json"

  @impl true
  def docs_url, do: "https://lucide.dev/icons/"

  # No stroke-width: a <symbol>'s presentation attributes bind the cloned
  # content and would override the width the outer <svg> passes down.
  @impl true
  def symbol_attrs do
    [
      {"fill", "none"},
      {"stroke", "currentColor"},
      {"stroke-linecap", "round"},
      {"stroke-linejoin", "round"}
    ]
  end

  @impl true
  def normalize(map) when is_map(map) and map_size(map) > 0 do
    if Enum.all?(map, fn {name, nodes} -> is_binary(name) and is_list(nodes) end) do
      {:ok,
       Map.new(map, fn {name, nodes} -> {name, %{"viewBox" => "0 0 24 24", "nodes" => nodes}} end)}
    else
      :error
    end
  end

  def normalize(_), do: :error
end
