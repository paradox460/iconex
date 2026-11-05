defmodule Iconex.SetTest do
  use ExUnit.Case, async: true

  alias Iconex.Set.Lucide

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
end
