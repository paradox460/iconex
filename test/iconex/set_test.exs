defmodule Iconex.SetTest do
  use ExUnit.Case, async: true

  alias Iconex.Set.{Carbon, Lucide}

  describe "Lucide.normalize/1" do
    test "adds Lucide's viewBox and keeps the nodes" do
      nodes = [["path", %{"d" => "M1 1"}], ["g", %{}, [["circle", %{"r" => "2"}]]]]

      assert Lucide.normalize(%{"house" => nodes}) ==
               {:ok, %{"house" => %{"viewBox" => "0 0 24 24", "nodes" => nodes}}}
    end

    test "rejects data that is not a non-empty map of node lists" do
      assert Lucide.normalize(%{}) == :error
      assert Lucide.normalize(%{"x" => "notalist"}) == :error
      assert Lucide.normalize([]) == :error
    end
  end

  describe "Carbon.normalize/1" do
    defp output(size, viewbox, content) do
      %{
        "size" => size,
        "descriptor" => %{
          "elem" => "svg",
          "attrs" => %{"viewBox" => viewbox},
          "content" => content
        }
      }
    end

    defp path(d), do: %{"elem" => "path", "attrs" => %{"d" => d}}

    test "prefers the 32px artwork, falling back to the glyph" do
      data = %{
        "icons" => [
          %{
            "name" => "add",
            "output" => [
              output(16, "0 0 16 16", [path("small")]),
              output(32, "0 0 32 32", [path("large")]),
              output("glyph", "0 0 16 16", [path("glyph")])
            ]
          },
          %{"name" => "caution", "output" => [output("glyph", "0 0 16 16", [path("g")])]}
        ]
      }

      assert {:ok, icons} = Carbon.normalize(data)
      assert icons["add"] == %{"viewBox" => "0 0 32 32", "nodes" => [["path", %{"d" => "large"}]]}
      assert icons["caution"] == %{"viewBox" => "0 0 16 16", "nodes" => [["path", %{"d" => "g"}]]}
    end

    test "stringifies numeric attrs and nests children" do
      group = %{
        "elem" => "g",
        "attrs" => %{"id" => "a"},
        "content" => [%{"elem" => "rect", "attrs" => %{"width" => 4}}]
      }

      data = %{"icons" => [%{"name" => "x", "output" => [output(32, "0 0 32 32", [group])]}]}

      assert {:ok, %{"x" => %{"nodes" => [["g", %{"id" => "a"}, [["rect", %{"width" => "4"}]]]]}}} =
               Carbon.normalize(data)
    end

    test "rejects data without icons" do
      assert Carbon.normalize(%{"icons" => []}) == :error
      assert Carbon.normalize(%{}) == :error
    end
  end
end
