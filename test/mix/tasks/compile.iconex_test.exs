defmodule Mix.Tasks.Compile.IconexTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Compile.Iconex, as: Compiler

  # Each test runs inside a throwaway Mix project. Fixture modules are
  # compiled in this VM, so real HEEx output is scanned, and their .beam
  # files are written to the project's compile path, as `mix compile` would.
  setup do
    root = Path.join(System.tmp_dir!(), "iconex-compiler-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)

      for key <- [:lucide, :carbon, :output_path],
          do: Application.delete_env(:iconex, key)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "finds literal icon names however the call is written", %{root: root} do
    in_fixture(root, fn ->
      compile!("""
      defmodule Fixture.Page do
        use Phoenix.Component
        import Iconex, only: [lucide: 1]
        alias Iconex, as: L

        def remote(assigns), do: ~H[<Iconex.lucide name="house" />]
        def imported(assigns), do: ~H[<.lucide name={"zap"} class="x" />]
        def aliased(assigns), do: ~H[<L.lucide name="circle" />]
        def dynamic(assigns), do: ~H[<Iconex.lucide name={@icon} />]
        def hinted, do: Iconex.hint(:lucide, ~w[chevron-up chevron-down])
      end
      """)

      assert {:ok, []} = run()

      assert symbols() ==
               [
                 "lucide-chevron-down",
                 "lucide-chevron-up",
                 "lucide-circle",
                 "lucide-house",
                 "lucide-zap"
               ]
    end)
  end

  test "ignores other icon components and non-literal text", %{root: root} do
    in_fixture(root, fn ->
      compile!("""
      defmodule Fixture.CoreComponents do
        use Phoenix.Component
        attr :name, :string, required: true
        def icon(assigns), do: ~H[<span class={@name} />]
      end

      defmodule Fixture.Other do
        use Phoenix.Component
        import Fixture.CoreComponents

        @moduledoc ~S(<Iconex.lucide name="mail" />)
        def page(assigns) do
          ~H\"\"\"
          <.icon name="hero-x-mark" />
          <input name="search" />
          <Iconex.lucide name="house" />
          \"\"\"
        end
      end
      """)

      assert {:ok, []} = run()
      assert symbols() == ["lucide-house"]
    end)
  end

  test "unknown names fail the build at the calling line", %{root: root} do
    in_fixture(root, fn ->
      file = Path.join(root, "lib/page.ex")

      compile!(
        """
        defmodule Fixture.Typo do
          use Phoenix.Component

          def page(assigns) do
            ~H\"\"\"
            <Iconex.lucide name="house" />
            <Iconex.lucide name="hous" />
            \"\"\"
          end
        end
        """,
        file
      )

      assert {:error, [diagnostic]} = run()
      assert diagnostic.message =~ ~s(unknown lucide icon "hous")
      assert diagnostic.file == file
      assert diagnostic.position == 7
      refute File.exists?(sprite())
    end)
  end

  test "collects icons from every set into one sprite", %{root: root} do
    in_fixture(root, fn ->
      compile!("""
      defmodule Fixture.Mixed do
        use Phoenix.Component
        import Iconex, only: [carbon: 1]

        def page(assigns) do
          ~H\"\"\"
          <Iconex.lucide name="house" />
          <Iconex.carbon name="add" />
          <.carbon name="close" />
          \"\"\"
        end

        def hinted, do: Iconex.hint(:carbon, ~w[checkmark])
      end
      """)

      assert {:ok, []} = run()
      assert symbols() == ["carbon-add", "carbon-checkmark", "carbon-close", "lucide-house"]
    end)
  end

  test "unknown names fail per set", %{root: root} do
    in_fixture(root, fn ->
      file = Path.join(root, "lib/page.ex")

      compile!(
        """
        defmodule Fixture.CarbonTypo do
          use Phoenix.Component

          def page(assigns) do
            ~H\"\"\"
            <Iconex.lucide name="house" />
            <Iconex.carbon name="ad" />
            \"\"\"
          end
        end
        """,
        file
      )

      assert {:error, [diagnostic]} = run()
      assert diagnostic.message =~ ~s(unknown carbon icon "ad")
      assert diagnostic.file == file
      assert diagnostic.position == 7
    end)
  end

  test "unknown names in :extra_icons fail the build", %{root: root} do
    in_fixture(root, fn ->
      Application.put_env(:iconex, :lucide, extra_icons: ["zapp"])

      assert {:error, [diagnostic]} = run()

      assert diagnostic.message =~
               ~s(unknown lucide icon "zapp" in config :iconex, lucide: [extra_icons)
    end)
  end

  test "tracks changes per module, including removals", %{root: root} do
    in_fixture(root, fn ->
      compile!(~S|defmodule Fixture.A do
        use Phoenix.Component
        def a(assigns), do: ~H[<Iconex.lucide name="house" />]
      end|)

      compile!(~S|defmodule Fixture.B do
        use Phoenix.Component
        def b(assigns), do: ~H[<Iconex.lucide name="zap" />]
      end|)

      assert {:ok, []} = run()
      assert symbols() == ["lucide-house", "lucide-zap"]
      assert {:noop, []} = run()

      File.rm!(beam(Fixture.B))
      assert {:ok, []} = run()
      assert symbols() == ["lucide-house"]

      File.rm!(beam(Fixture.A))
      assert {:ok, []} = run()
      assert symbols() == []
    end)
  end

  test "rewrites the sprite when settings change though the icons do not", %{root: root} do
    data = Iconex.data_path(:lucide)
    {:ok, %File.Stat{mtime: mtime}} = File.stat(data, time: :posix)
    on_exit(fn -> File.touch!(data, mtime) end)

    in_fixture(root, fn ->
      Application.put_env(:iconex, :lucide, extra_icons: ["house"])
      assert {:ok, []} = run()

      File.write!(sprite(), "<svg>stale</svg>")
      File.touch!(data, mtime + 60)

      assert {:ok, []} = run()
      assert symbols() == ["lucide-house"]
    end)
  end

  test "warns about modules compiled without debug info", %{root: root} do
    in_fixture(root, fn ->
      compile!(
        ~S|defmodule Fixture.NoDebug do
          use Phoenix.Component
          def a(assigns), do: ~H[<Iconex.lucide name="house" />]
        end|,
        "nofile",
        false
      )

      assert {:ok, [warning]} = run()
      assert warning.severity == :warning
      assert warning.message =~ "Elixir.Fixture.NoDebug.beam"
    end)
  end

  test "writes to :output_path", %{root: root} do
    in_fixture(root, fn ->
      Application.put_env(:iconex, :lucide, extra_icons: ["house"])
      Application.put_env(:iconex, :output_path, "priv/static/icons/sprite.svg")

      assert {:ok, []} = run()
      assert symbols(Path.expand("priv/static/icons/sprite.svg")) == ["lucide-house"]
    end)
  end

  test "refuses to run before the Elixir compiler", %{root: root} do
    in_fixture(root, [compilers: [:iconex, :elixir, :app]], fn ->
      assert {:error, [diagnostic]} = run()
      assert diagnostic.message =~ "must run after :elixir"
    end)
  end

  defp in_fixture(root, opts \\ [], fun) do
    compilers = Keyword.get(opts, :compilers, [:elixir, :app, :iconex])
    name = :"fixture#{System.unique_integer([:positive])}"
    module = Module.concat(["Fixture#{System.unique_integer([:positive])}", MixProject])

    File.write!(Path.join(root, "mix.exs"), """
    defmodule #{inspect(module)} do
      use Mix.Project
      def project, do: [app: #{inspect(name)}, version: "0.1.0", compilers: #{inspect(compilers)}]
    end
    """)

    Mix.Project.in_project(name, root, fn _ ->
      File.mkdir_p!(Mix.Project.compile_path())

      try do
        fun.()
      after
        for {mod, _} <- :code.all_loaded(),
            String.starts_with?(Atom.to_string(mod), "Elixir.Fixture.") do
          :code.purge(mod)
          :code.delete(mod)
        end
      end
    end)
  end

  # `mix test` turns debug_info off while `mix compile` keeps it on, so match
  # a real build unless a test says otherwise.
  defp compile!(source, file \\ "nofile", debug_info \\ true) do
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, debug_info)

    try do
      for {module, bin} <- Code.compile_string(source, file) do
        File.write!(beam(module), bin)
      end
    after
      Code.put_compiler_option(:debug_info, previous)
    end
  end

  defp beam(module), do: Path.join(Mix.Project.compile_path(), "#{module}.beam")

  defp sprite, do: Path.expand("priv/static/images/iconex.svg")

  # Diagnostics are printed to stderr as well as returned.
  defp run do
    parent = self()
    ExUnit.CaptureIO.capture_io(:stderr, fn -> send(parent, {:result, Compiler.run([])}) end)
    assert_received {:result, result}
    result
  end

  defp symbols(path \\ sprite()) do
    ~r/id="((?:lucide|carbon)-[^"]+)"/
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> List.flatten()
  end
end
