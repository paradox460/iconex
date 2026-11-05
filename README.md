# Iconex

[Lucide](https://lucide.dev) and [IBM Carbon](https://carbondesignsystem.com/elements/icons/library/)
icons for Phoenix, delivered as an SVG sprite that contains only the icons your
app uses.

After your code compiles, a Mix compiler finds every `Iconex.lucide` and
`Iconex.carbon` call with a literal name and writes
`priv/static/images/iconex.svg` with just those icons. Each icon renders as an
`<svg><use href="/images/iconex.svg#lucide-house"/></svg>`, so the browser
downloads the sprite once and caches it. Misspelled icon names fail the build.

## Installation

With [Igniter](https://hexdocs.pm/igniter), run:

```sh
mix igniter.install iconex
```

This adds the dependency, registers the `:iconex` compiler, puts
`Iconex.sprite_tag/0` at the top of `<body>` in your root layout, enables
inline delivery in `config/dev.exs`, and gitignores the generated sprite.

Alternatively, do it yourself. Add `iconex` to your dependencies and register its
compiler after the default ones in `mix.exs`:

```elixir
def project do
  [
    # ...
    compilers: Mix.compilers() ++ [:iconex]
  ]
end

def deps do
  [
    {:iconex, "~> 0.1.0"}
  ]
end
```

Put the sprite tag at the top of `<body>` in your root layout. With the default
delivery it renders nothing, but it's what makes inline delivery work:

```heex
<body>
  <%= Iconex.sprite_tag() %>
  ...
</body>
```

## Usage

```heex
<Iconex.lucide name="house" />
<Iconex.lucide name="arrow-up-right" size={20} class="text-zinc-500" />

<Iconex.carbon name="add" />
<Iconex.carbon name="logo--github" size={32} />
```

Any other attribute is passed to the outer `<svg>`. `import Iconex` lets you
write `<.lucide name="house" />` and `<.carbon name="add" />`; the compiler
finds those calls too, and ignores other components such as the `icon` in
Phoenix's generated `CoreComponents`.

- **Lucide**: kebab-case names from [lucide.dev/icons](https://lucide.dev/icons/).
  Default size `24`. `stroke_width` takes any positive number (`2` by default,
  or `config :iconex, lucide: [stroke_width: 1.5]`).
- **Carbon**: names from the
  [Carbon icon library](https://carbondesignsystem.com/elements/icons/library/),
  as published in `@carbon/icons`, e.g. `"add"`, `"arrow--right"`,
  `"logo--github"`. Names are case-sensitive. Default size `16`; the 32px
  artwork is used at every size.

The compiler only sees literal names. For names chosen at runtime, list them
next to the code that picks them:

```elixir
Iconex.hint(:lucide, ~w[chevron-up chevron-down])
```

or in config with `config :iconex, lucide: [extra_icons: ~w[chevron-up chevron-down]]`.

The compiler reads the debug info Mix stores in compiled modules. That's on by
default; a module built with `debug_info: false` is skipped with a warning.

### Choosing icon sets

Both sets are enabled by default. To compile in only some of them:

```elixir
# config/config.exs
config :iconex, sets: [:lucide]
```

A disabled set's component is not defined, and the compiler reports any call
to it. `:sets` is read when iconex compiles, so run
`mix deps.compile iconex --force` after changing it.

## Inline delivery for development

To embed the sprite in each page instead of serving a static file:

```elixir
# config/dev.exs
config :iconex, delivery: :inline, otp_app: :my_app
```

`sprite_tag/0` then reads your app's generated sprite and picks up changes
without a server restart. `:delivery` is read when iconex compiles, so run
`mix deps.compile iconex --force` after changing it.

## Configuration

| Option | Default | Read at |
|---|---|---|
| `:sets` | `[:lucide, :carbon]` | compile time |
| `:delivery` | `:external` | compile time |
| `:otp_app` | none; inline mode then embeds every icon | runtime |
| `:output_path` | `"priv/static/images/iconex.svg"` | build |
| `:sprite_url` | `"/images/iconex.svg"` | compile time |
| `<set>: [data_path: ...]` | the copy bundled with iconex | compile time |
| `<set>: [extra_icons: ...]` | `[]` | build |
| `lucide: [stroke_width: ...]` | `2` | compile time |

`<set>` is `lucide` or `carbon`, e.g.
`config :iconex, carbon: [extra_icons: ~w[close]]`.

## Newer icons

Iconex ships a copy of each set's data. To pull a newer release of a set
without waiting for an iconex update, run this in your project:

```sh
mix iconex.download lucide                  # latest lucide-static
mix iconex.download carbon --version 11.92.0
```

It writes `priv/iconex/SET.json` and prints the config line that points iconex
at it. Once that config is set, later downloads recompile iconex for you.

## Development

The icon data isn't kept in git; it's only bundled into the Hex package. After
cloning, fetch both sets before running the tests:

```sh
mix iconex.download lucide
mix iconex.download carbon
mix test
```

`mix hex.build` and `mix hex.publish` download the releases pinned by
`@set_versions` in `mix.exs` first, so the package always ships those
versions. A path or git dependency on iconex needs the same downloads inside
its checkout.

## Adding an icon set

Each set is a module implementing the `Iconex.Set` behaviour. Its docs list
the steps to add one.

## Migrating from lucidex

Iconex is the renamed [lucidex](https://github.com/paradox460/lucidex). To
migrate:

| lucidex | iconex |
|---|---|
| `{:lucidex, …}` | `{:iconex, …}` |
| `:lucidex` compiler | `:iconex` |
| `Lucidex.icon` / `<.icon>` | `Iconex.lucide` / `<.lucide>` |
| `Lucidex.lucidex_hint(list)` | `Iconex.hint(:lucide, list)` |
| `Lucidex.sprite_tag()` | `Iconex.sprite_tag()` |
| `extra_icons:` | `lucide: [extra_icons:]` |
| `stroke_width:` | `lucide: [stroke_width:]` |
| `icon_nodes_path:` | `lucide: [data_path:]`, re-download with `mix iconex.download lucide` |
| `lucide.svg` | `iconex.svg` (update `.gitignore`) |
| `#lucide-*` | `#lucide-*` (unchanged) |
| `mix lucidex.download` | `mix iconex.download lucide` |

The `lucide-icon` CSS class on rendered icons is now `iconex iconex-lucide`.

## License

MIT. Lucide icons are licensed under the ISC license and Carbon icons under
the Apache License 2.0; their license texts are in [`licenses/`](licenses/).
