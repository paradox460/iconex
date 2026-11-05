defmodule IconexTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  describe "render_nodes/1" do
    test "renders Lucide's 2-element nodes as self-closing tags" do
      assert Iconex.render_nodes([["path", %{"d" => "M1 1"}]]) == ~s(<path d="M1 1"/>)
    end

    test "renders 3-element nodes with children" do
      nodes = [["g", %{"id" => "a"}, [["circle", %{"r" => "2"}]]]]
      assert Iconex.render_nodes(nodes) == ~s(<g id="a"><circle r="2"/></g>)
    end

    test "escapes attribute values" do
      assert Iconex.render_nodes([["path", %{"d" => ~s(a"b<c&d)}]]) ==
               ~s(<path d="a&quot;b&lt;c&amp;d"/>)
    end

    test "renders every icon in the bundled dataset" do
      {:ok, all} = Iconex.Set.read(Iconex.data_path(:lucide))
      svg = Iconex.build_sprite(for(name <- Map.keys(all), do: {:lucide, name}), %{lucide: all})
      assert svg =~ ~s(id="lucide-house")
    end
  end

  describe "build_sprite/2" do
    test "includes only requested, known icons" do
      all = %{lucide: %{"a" => lucide_icon("A"), "b" => lucide_icon("B")}}
      svg = Iconex.build_sprite([{:lucide, "b"}, {:lucide, "missing"}], all)

      assert svg =~ ~s(id="lucide-b")
      refute svg =~ ~s(id="lucide-a")
      refute svg =~ "missing"
    end

    # A width on the <symbol> would override the one `lucide/1` sets on the outer <svg>.
    test "leaves the stroke width to the referencing icon" do
      svg = Iconex.build_sprite([{:lucide, "a"}], %{lucide: %{"a" => lucide_icon("A")}})

      refute svg =~ "stroke-width"
    end

    test "applies each set's presentation attributes to its symbols" do
      all = %{
        carbon: %{"a" => %{"viewBox" => "0 0 32 32", "nodes" => [["path", %{"d" => "A"}]]}},
        lucide: %{"b" => lucide_icon("B")}
      }

      svg = Iconex.build_sprite([{:carbon, "a"}, {:lucide, "b"}], all)
      [carbon] = Regex.run(~r/<symbol id="carbon-a"[^>]*>/, svg)
      [lucide] = Regex.run(~r/<symbol id="lucide-b"[^>]*>/, svg)

      assert carbon =~ ~s(viewBox="0 0 32 32")
      assert carbon =~ ~s(fill="currentColor")
      refute carbon =~ "stroke="
      assert lucide =~ ~s(stroke="currentColor")
    end
  end

  describe "lucide/1 with the default :external delivery" do
    test "references the external sprite" do
      html = render_component(&Iconex.lucide/1, name: "house", size: 16, class: "w-4")

      assert html =~ ~s(href="/images/iconex.svg#lucide-house")
      assert html =~ ~s(width="16")
      assert html =~ ~s(class="iconex iconex-lucide w-4")
    end

    test "raises on an unknown icon name" do
      assert_raise ArgumentError, ~r/unknown lucide icon "nope-not-real"/, fn ->
        render_component(&Iconex.lucide/1, name: "nope-not-real")
      end
    end

    test "sprite_tag/0 emits nothing" do
      assert Iconex.sprite_tag() == {:safe, ""}
    end
  end

  describe "carbon/1 with the default :external delivery" do
    test "references the external sprite with the icon's viewBox" do
      html = render_component(&Iconex.carbon/1, name: "add")

      assert html =~ ~s(href="/images/iconex.svg#carbon-add")
      assert html =~ ~s(viewBox="0 0 32 32")
      assert html =~ ~s(width="16")
      assert html =~ ~s(fill="currentColor")
    end

    test "uses the glyph viewBox for glyph-only icons" do
      assert render_component(&Iconex.carbon/1, name: "caution") =~ ~s(viewBox="0 0 16 16")
    end

    test "raises on an unknown icon name" do
      assert_raise ArgumentError, ~r/unknown carbon icon "nope"/, fn ->
        render_component(&Iconex.carbon/1, name: "nope")
      end
    end
  end

  describe "inline_sprite/0" do
    setup do
      path = Application.app_dir(:iconex, "priv/static/images/iconex.svg")
      File.rm_rf!(Path.dirname(path))

      on_exit(fn ->
        Application.delete_env(:iconex, :otp_app)
        File.rm_rf!(Application.app_dir(:iconex, "priv/static"))
      end)

      %{path: path}
    end

    test "embeds every icon when no :otp_app is configured" do
      svg = Iconex.inline_sprite()
      assert svg =~ ~s(id="lucide-house")
      assert svg =~ ~s(id="lucide-zap")
    end

    test "falls back to every icon when the host sprite is missing" do
      Application.put_env(:iconex, :otp_app, :iconex)
      assert Iconex.inline_sprite() =~ ~s(id="lucide-zap")
    end

    test "serves the host's pruned sprite and picks up rewrites", %{path: path} do
      Application.put_env(:iconex, :otp_app, :iconex)
      File.mkdir_p!(Path.dirname(path))

      File.write!(path, "<svg>one</svg>")
      assert Iconex.inline_sprite() == "<svg>one</svg>"

      File.write!(path, "<svg>second</svg>")
      assert Iconex.inline_sprite() == "<svg>second</svg>"
    end
  end

  defp lucide_icon(d), do: %{"viewBox" => "0 0 24 24", "nodes" => [["path", %{"d" => d}]]}
end
