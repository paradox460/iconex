defmodule Iconex.Set.Carbon do
  @moduledoc """
  [IBM Carbon](https://carbondesignsystem.com/elements/icons/library/) icons,
  from the `@carbon/icons` npm package's `metadata.json`. Fill-based.

  Each icon uses its 32px master artwork (viewBox `0 0 32 32`), or its glyph
  artwork for the few glyph-only icons (viewBox `0 0 16 16`). Size-specific
  16/20/24px variants are not included. Names are kept verbatim, so they are
  case-sensitive and include deprecated icons.
  """

  @behaviour Iconex.Set

  @impl true
  def npm_package, do: "@carbon/icons"

  @impl true
  def data_url(version), do: "https://cdn.jsdelivr.net/npm/@carbon/icons@#{version}/metadata.json"

  @impl true
  def docs_url, do: "https://carbondesignsystem.com/elements/icons/library/"

  @impl true
  def symbol_attrs, do: [{"fill", "currentColor"}]

  @impl true
  def normalize(%{"icons" => [_ | _] = icons}) do
    normalized =
      for %{"name" => name, "output" => outputs} when is_binary(name) and is_list(outputs) <-
            icons,
          descriptor = artwork(outputs),
          descriptor != nil,
          into: %{} do
        {name,
         %{
           "viewBox" => Map.fetch!(descriptor["attrs"], "viewBox"),
           "nodes" => Enum.map(descriptor["content"], &svg_node/1)
         }}
      end

    if map_size(normalized) > 0, do: {:ok, normalized}, else: :error
  catch
    :invalid -> :error
  end

  def normalize(_), do: :error

  defp artwork(outputs) do
    output =
      Enum.find(outputs, &match?(%{"size" => 32}, &1)) ||
        Enum.find(outputs, &match?(%{"size" => "glyph"}, &1))

    case output do
      nil ->
        nil

      %{"descriptor" => %{"attrs" => %{"viewBox" => vb}, "content" => c} = d}
      when is_binary(vb) and is_list(c) ->
        d

      _ ->
        throw(:invalid)
    end
  end

  defp svg_node(%{"elem" => elem, "attrs" => attrs} = node)
       when is_binary(elem) and is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {k, to_string(v)} end)

    case node["content"] do
      [_ | _] = children -> [elem, attrs, Enum.map(children, &svg_node/1)]
      _ -> [elem, attrs]
    end
  end

  defp svg_node(_), do: throw(:invalid)
end
