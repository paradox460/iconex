defmodule Iconex do
  @moduledoc """
  Auto tree-shaken icons for Phoenix, from several icon sets.

  ## Usage

  Each icon set has its own component:

      <Iconex.lucide name="house" class="w-5 h-5" />
      <Iconex.lucide name="circle" size={20} />

  `import Iconex` lets you write `<.lucide name="house" />` instead.

  ## Icon sets

  | Set | Component | Names |
  |-----|-----------|-------|
  | [Lucide](https://lucide.dev/icons/) | `lucide/1` | `"house"`, `"arrow-up-right"` |

  Every set is enabled by default. To compile in only some of them:

      # config/config.exs
      config :iconex, sets: [:lucide]

  The component of a disabled set is not defined, and the compiler reports
  every call to it.

  ## How it works

  `Mix.Tasks.Compile.Iconex` reads your compiled modules after each build
  and writes a pruned `priv/static/images/iconex.svg` containing only the
  icons used, from every set. Register it after the default compilers in
  `mix.exs`:

      compilers: Mix.compilers() ++ [:iconex]

  Icons are rendered using [svg
  sprites](https://css-tricks.com/svg-sprites-use-better-icon-fonts/) via
  `<use>` references to symbols named `#<set>-<name>`, e.g. `#lucide-house`.

  Icon names are validated against the bundled data in `priv/sets/`; run
  `mix iconex.download SET` to use a newer release of a set.

  In the case of icon names that are dynamically called at runtime, such as a
  conditional switching between two icons, you must _hint_ the compiler, so it
  emits both icons. See `hint/2` for details.

  ## Root layout setup

  Place `Iconex.sprite_tag/0` once at the top of `<body>`:

      # root.html.heex
      <%= Iconex.sprite_tag() %>

  ## Delivery modes

  The default delivery is `:external`: `sprite_tag/0` emits nothing and icons
  reference `/images/iconex.svg`, which the browser fetches and caches once.

  For development you can embed the sprite in the page instead, so no static
  file needs serving:

      # config/dev.exs
      config :iconex, delivery: :inline, otp_app: :my_app

  This has added advantage that hot reloads can render new sprites without
  additional network requests.

  In `:inline` mode `sprite_tag/0` reads the pruned sprite from `:otp_app`
  (at `:output_path`) and re-reads it whenever the compiler rewrites it.
  Without `:otp_app` it embeds every icon.

  `:sets`, `:delivery`, `:sprite_url`, and each set's `:data_path` (and
  Lucide's `:stroke_width`) are read at compile time, so run
  `mix deps.compile iconex --force` after changing them.

  ## Per-set configuration

  Options that apply to one set live under its id:

      config :iconex,
        lucide: [stroke_width: 1.5, extra_icons: ~w[loader]]

  ## Lucide stroke width

  Every Lucide icon is drawn at stroke width `2`, Lucide's own, unless the
  `stroke_width` attribute says otherwise. Set an app-wide default with:

      config :iconex, lucide: [stroke_width: 1.5]

  The width is in the 24-unit viewBox, so it scales with the icon.

  ## Serving the static file

  Phoenix's default `Plug.Static` setup serves `priv/static/images`, which is
  where the sprite is written, so the defaults need no configuration.
  If you serve static files from elsewhere, set both the file location and the
  URL it is served at:

      config :iconex,
        output_path: "priv/static/assets/iconex.svg",
        sprite_url: "/assets/iconex.svg"

  ## Icon data

  `mix iconex.download SET` fetches a set's data. To use a copy newer than
  the one bundled with iconex, point the set's `:data_path` at it (the path
  must be absolute):

      config :iconex, lucide: [data_path: Path.expand("../priv/iconex/lucide.json", __DIR__)]
  """

  use Phoenix.Component

  @sets Application.compile_env(:iconex, :sets, Iconex.Set.ids())

  unless is_list(@sets) and @sets != [] and Enum.all?(@sets, &(&1 in Iconex.Set.ids())) do
    raise ArgumentError,
          "config :iconex, :sets must be a non-empty list of #{inspect(Iconex.Set.ids())}, got: #{inspect(@sets)}"
  end

  # Hosts may point a set at their own downloaded copy (see `mix iconex.download`);
  # the path must be absolute because deps compile with cwd = deps/iconex.
  @data_paths (for set <- @sets, into: %{} do
                 path =
                   case Application.compile_env(:iconex, [set, :data_path]) do
                     nil ->
                       Application.app_dir(:iconex, "priv/sets/#{set}.json")

                     path when is_binary(path) ->
                       Path.type(path) == :absolute ||
                         raise ArgumentError,
                               "config :iconex, #{set}: [data_path: ...] must be an absolute path, got: #{inspect(path)}. " <>
                                 ~s|Use Path.expand("../priv/iconex/#{set}.json", __DIR__) in config/config.exs.|

                       path
                   end

                 {set, path}
               end)

  # Recompile this module when a data file changes.
  for path <- Map.values(@data_paths), do: @external_resource(path)

  # Compile-time: load every enabled set so every icon works in dev/test.
  @icons (for {set, path} <- @data_paths, into: %{} do
            icons =
              if File.exists?(path) do
                case Iconex.Set.read(path) do
                  {:ok, icons} ->
                    icons

                  :error ->
                    raise "Iconex: #{path} is not valid iconex icon data. Run `mix iconex.download #{set}`."
                end
              else
                IO.warn(
                  "Iconex: #{set} icon data not found at #{path}; no #{set} icons are available. " <>
                    "Run `mix iconex.download #{set}`.",
                  []
                )

                %{}
              end

            {set, icons}
          end)

  @doc false
  def enabled_sets, do: @sets

  @doc false
  def data_path(set), do: Map.fetch!(@data_paths, set)

  # One literal for the whole dataset, shared by every caller.
  defp icons, do: @icons

  # Compile-time delivery mode. Defaults to :external; opt into :inline per env.
  @delivery Application.compile_env(:iconex, :delivery, :external)

  unless @delivery in [:inline, :external] do
    raise ArgumentError,
          "config :iconex, :delivery must be :inline or :external, got: #{inspect(@delivery)}"
  end

  if :lucide in @sets do
    @lucide_stroke_width Application.compile_env(:iconex, [:lucide, :stroke_width], 2)

    unless is_number(@lucide_stroke_width) and @lucide_stroke_width > 0 do
      raise ArgumentError,
            "config :iconex, lucide: [stroke_width: ...] must be a positive number, got: #{inspect(@lucide_stroke_width)}"
    end

    @doc """
    Renders a [Lucide](https://lucide.dev/icons/) icon.

    ## Attributes

    * `name` (required) kebab-case icon name, e.g. `"house"`, `"arrow-up-right"`
    * `size` integer pixel size applied to `width` and `height` (default `24`)
    * `class` CSS class string, added after `iconex iconex-lucide`
    * `stroke_width` stroke width, any positive number (default `2`, or
      `config :iconex, lucide: [stroke_width: ...]`)
    * Any other attribute is forwarded to the outer `<svg>` element.

    ## Examples

        <Iconex.lucide name="house" />
        <Iconex.lucide name="loader" class="loading-icon" size={20} />
    """
    attr :name, :string, required: true
    attr :size, :integer, default: 24
    attr :class, :string, default: nil
    attr :stroke_width, :any, default: @lucide_stroke_width
    attr :rest, :global

    def lucide(%{name: name} = assigns) do
      validate!(:lucide, name)

      ~H"""
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width={@size}
        height={@size}
        viewBox={viewbox(:lucide, @name)}
        fill="none"
        stroke="currentColor"
        stroke-width={@stroke_width}
        stroke-linecap="round"
        stroke-linejoin="round"
        class={["iconex", "iconex-lucide", @class]}
        {@rest}
      >
        <use href={icon_href(:lucide, @name)} />
      </svg>
      """
    end
  end

  @doc """
  Marks icon names of `set` as used so the compiler includes them in the sprite.

  Use it for names only known at runtime, next to the code that picks them:

      icon = if @open, do: "chevron-up", else: "chevron-down"
      Iconex.hint(:lucide, ~w[chevron-up chevron-down])

  The compiler only counts calls whose set is a literal atom and whose names
  are literal strings, so `~w[...]` works and names built at runtime don't.
  Returns the list unchanged.
  """
  def hint(set, names) when is_atom(set) and is_list(names), do: names

  # Name validation, to make debugging easier.
  defp validate!(set, name) do
    unless Map.has_key?(Map.fetch!(icons(), set), name) do
      raise ArgumentError,
            "Iconex: unknown #{set} icon #{inspect(name)}. " <>
              "Check the spelling against #{Iconex.Set.module!(set).docs_url()} ."
    end
  end

  defp viewbox(set, name), do: icons()[set][name]["viewBox"]

  @doc """
  Emits the SVG sprite element to be placed once in your root layout.

  In `:inline` delivery mode this embeds the sprite as a hidden `<svg>` block
  so that `<use href="#lucide-...">` fragment references resolve without an
  extra HTTP request. The sprite is read from
  `priv/static/images/iconex.svg` of the app configured as `:otp_app`, and
  re-read whenever that file changes. Without `:otp_app`, or before the
  compiler has written the file, every icon is embedded.

  In `:external` delivery mode (the default) this emits nothing; the sprite is
  served from `:sprite_url` and components reference it with a full path.

  Place this at the very top of `<body>` in `root.html.heex`:

      <body>
        <%= Iconex.sprite_tag() %>
        ...
      </body>
  """
  if @delivery == :inline do
    def sprite_tag, do: {:safe, inline_sprite()}
  else
    def sprite_tag, do: {:safe, ""}
  end

  # Decided at compile time, so there's zero branching at runtime.
  if @delivery == :external do
    @sprite_url Application.compile_env(:iconex, :sprite_url, "/images/iconex.svg")
    defp icon_href(set, name), do: "#{@sprite_url}##{set}-#{name}"
  else
    defp icon_href(set, name), do: "##{set}-#{name}"
  end

  @sprite_key {__MODULE__, :inline_sprite}

  # Inline mode is a dev convenience, so a File.stat per sprite_tag call is an
  # acceptable price for picking up compiler reruns without a restart. The
  # persistent_term is only rewritten when the file's mtime or size changes
  # (mtime alone has one-second granularity).
  @doc false
  def inline_sprite do
    with app when not is_nil(app) <- Application.get_env(:iconex, :otp_app),
         output = Application.get_env(:iconex, :output_path, "priv/static/images/iconex.svg"),
         path = Path.expand(output, Application.app_dir(app)),
         {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(path, time: :posix) do
      cached({path, mtime, size}, fn -> File.read!(path) end)
    else
      _ ->
        cached(:full, fn ->
          all = icons()
          build_sprite(for({set, icons} <- all, name <- Map.keys(icons), do: {set, name}), all)
        end)
    end
  end

  defp cached(version, build) do
    case :persistent_term.get(@sprite_key, nil) do
      {^version, svg} ->
        svg

      _ ->
        svg = build.()
        :persistent_term.put(@sprite_key, {version, svg})
        svg
    end
  end

  @doc false
  def build_sprite(refs, icons_by_set) do
    symbols =
      refs
      |> Enum.sort()
      |> Enum.map_join("\n", fn {set, name} ->
        case icons_by_set do
          %{^set => %{^name => %{"viewBox" => viewbox, "nodes" => nodes}}} ->
            # The set's attrs carry no stroke-width: a <symbol>'s presentation
            # attributes bind the cloned content and would override the width
            # the outer <svg> passes down, making `lucide/1`'s `stroke_width` a
            # no-op.
            attrs =
              Enum.map_join(Iconex.Set.module!(set).symbol_attrs(), " ", fn {k, v} ->
                ~s(#{escape(k)}="#{escape(v)}")
              end)

            """
              <symbol id="#{set}-#{escape(name)}" viewBox="#{escape(viewbox)}" #{attrs}>
                #{render_nodes(nodes)}
              </symbol>
            """

          _ ->
            ""
        end
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">
    #{symbols}
    </svg>
    """
  end

  @doc false
  def render_nodes(nodes) do
    Enum.map_join(nodes, fn
      [tag, attrs] -> render_node(tag, attrs, [])
      [tag, attrs, children] -> render_node(tag, attrs, children)
    end)
  end

  defp render_node(tag, attrs, children) do
    tag = escape(tag)
    attr_str = Enum.map_join(attrs, " ", fn {k, v} -> ~s(#{escape(k)}="#{escape(v)}") end)
    inner = render_nodes(children)

    if inner == "" do
      "<#{tag} #{attr_str}/>"
    else
      "<#{tag} #{attr_str}>#{inner}</#{tag}>"
    end
  end

  # build_sprite/2 output is emitted as {:safe, ...}, bypassing HEEx escaping.
  defp escape(value) do
    {:safe, iodata} = Phoenix.HTML.html_escape(to_string(value))
    IO.iodata_to_binary(iodata)
  end
end
