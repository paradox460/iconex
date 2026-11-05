defmodule Mix.Tasks.Compile.Iconex do
  @moduledoc """
  A Mix compiler that finds the icons your compiled code uses and writes a
  pruned SVG sprite containing only those icons. Tree-shaking, but without all
  the messy JS.

  It reads the modules the Elixir compiler just built, so it must run after
  compilation:

      # mix.exs
      compilers: Mix.compilers() ++ [:iconex]

  The sprite is written to `priv/static/images/iconex.svg` in the current
  project, which Phoenix's `Plug.Static` serves at `/images/iconex.svg`. It
  holds the icons of every set, as symbols named `<set>-<name>`.

  ## Dynamic icon names

  For most usage, simply calling a set's component, such as `Iconex.lucide/1`,
  with a literal string is sufficient. However, if icon names are dynamically
  constructed at runtime (such as a conditional on which icon to display), you
  must "hint" the compiler with `Iconex.hint/2`.

  See `Iconex.hint/2` for more details.

  ## What gets found

  Every call to a set's component, such as `Iconex.lucide/1`, whose `name` is
  a literal string, however it was written: `<Iconex.lucide name="house" />`,
  `<.lucide name={"house"} />` through `import Iconex`, an alias, or a
  template loaded with `embed_templates`. Calls to other components, such as
  the `icon` in a generated Phoenix `CoreComponents`, are not counted.

  Names only known at runtime, such as `name={@icon}`, are invisible at build
  time. List them in the set's `:extra_icons` or pass a literal list to
  `Iconex.hint/2`:

      Iconex.hint(:lucide, ["chevron-up", "chevron-down"])

  A name that doesn't exist in its set fails the build, pointing at the file
  and line that referenced it. So does any use of a set that is not enabled in
  `config :iconex, :sets`.

  Scanning needs the modules' debug info, which Mix includes by default. A
  module compiled without it is skipped with a warning.

  ## Configuration

      # config/config.exs
      config :iconex,
        # Extra icon names to always include (for fully dynamic usages)
        lucide: [extra_icons: ~w[loader circle x]],

        # Where the sprite is written, relative to the project root
        output_path: "priv/static/images/iconex.svg"

  ## Recompilation

  The manifest records the icons found in each compiled module. Only modules
  whose `.beam` changed are read again, and the sprite is only rewritten when
  the overall set of icons changes.
  """

  use Mix.Task.Compiler

  @shortdoc "Generates a pruned SVG icon sprite from your compiled code"

  @manifest_vsn 1
  @manifest_name "iconex"
  @default_output "priv/static/images/iconex.svg"
  @set_ids Iconex.Set.ids()

  @impl true
  def manifests, do: [manifest_path()]

  @impl true
  def clean do
    File.rm(manifest_path())
    File.rm(sprite_path())
    :ok
  end

  @impl true
  def run(args) do
    case order_error() do
      nil -> run_checked(args)
      diagnostic -> fail([diagnostic])
    end
  end

  defp run_checked(args) do
    sets = Iconex.enabled_sets()

    missing =
      for set <- sets, path = Iconex.data_path(set), not File.exists?(path) do
        diagnostic(
          :error,
          "Iconex: #{set} icon data not found at #{path}. Run `mix iconex.download #{set}`.",
          nil,
          0
        )
      end

    if missing == [] do
      out = sprite_path()

      extra =
        for set <- @set_ids,
            name <- Keyword.get(Application.get_env(:iconex, set, []), :extra_icons, []),
            do: {set, name, nil, 0}

      beams = beam_stats()

      settings =
        {Application.spec(:iconex, :vsn), sets, Map.new(sets, &{&1, stat(Iconex.data_path(&1))}),
         extra, out}

      manifest = if "--force" in args, do: %{}, else: read_manifest()

      if manifest[:settings] == settings and manifest[:beams] == beams and File.exists?(out) do
        {:noop, []}
      else
        compile(sets, out, extra, beams, settings, manifest)
      end
    else
      fail(missing)
    end
  end

  defp compile(sets, out, extra, beams, settings, manifest) do
    case read_sets(sets) do
      {:ok, icons_by_set} -> compile(icons_by_set, sets, out, extra, beams, settings, manifest)
      {:error, diagnostics} -> fail(diagnostics)
    end
  end

  defp compile(icons_by_set, sets, out, extra, beams, settings, manifest) do
    cached = Map.get(manifest, :refs, %{})
    old_beams = Map.get(manifest, :beams, %{})

    # {path => refs | {:skipped, message}}, re-reading only changed beams.
    refs_by_beam =
      Map.new(beams, fn {path, stat} ->
        case {old_beams, cached} do
          {%{^path => ^stat}, %{^path => refs}} -> {path, refs}
          _ -> {path, read_refs(path)}
        end
      end)

    skipped =
      for {path, {:skipped, message}} <- refs_by_beam do
        diagnostic(:warning, "Iconex: skipped #{Path.relative_to_cwd(path)}: #{message}", nil, 0)
      end

    refs =
      Enum.flat_map(refs_by_beam, fn
        {_path, refs} when is_list(refs) -> refs
        _ -> []
      end) ++ extra

    {enabled, disabled} = refs |> Enum.uniq() |> Enum.split_with(&(elem(&1, 0) in sets))

    errors =
      for({set, _name, file, line} <- disabled, uniq: true, do: {set, file, line})
      |> Enum.map(fn {set, file, line} -> disabled_set(set, file, line) end)

    errors =
      errors ++
        for {set, name, file, line} <- enabled,
            not Map.has_key?(icons_by_set[set], name),
            do: unknown_icon(set, name, file, line)

    icons =
      enabled |> Enum.map(fn {set, name, _, _} -> {set, name} end) |> Enum.uniq() |> Enum.sort()

    Enum.each(skipped ++ errors, &Code.print_diagnostic/1)

    cond do
      errors != [] ->
        {:error, skipped ++ errors}

      # Same icons is not enough: new settings (an iconex upgrade, which can change the sprite's
      # markup, or new icon data) must rewrite it.
      icons == manifest[:icons] and manifest[:settings] == settings and File.exists?(out) ->
        write_manifest(settings, beams, refs_by_beam, icons)
        {:noop, skipped}

      true ->
        File.mkdir_p!(Path.dirname(out))
        File.write!(out, Iconex.build_sprite(icons, icons_by_set))
        write_manifest(settings, beams, refs_by_beam, icons)

        Mix.shell().info([
          :green,
          "Iconex ",
          :reset,
          "generated sprite with #{length(icons)} icon(s) → #{Path.relative_to_cwd(out)}"
        ])

        {:ok, skipped}
    end
  end

  defp read_sets(sets) do
    {icons_by_set, invalid} =
      Enum.reduce(sets, {%{}, []}, fn set, {acc, invalid} ->
        path = Iconex.data_path(set)

        case Iconex.Set.read(path) do
          {:ok, icons} ->
            {Map.put(acc, set, icons), invalid}

          :error ->
            message =
              "Iconex: #{path} is not valid iconex icon data. Run `mix iconex.download #{set}`."

            {acc, [diagnostic(:error, message, nil, 0) | invalid]}
        end
      end)

    if invalid == [], do: {:ok, icons_by_set}, else: {:error, Enum.reverse(invalid)}
  end

  # Scanning an earlier compiler's leftovers would silently produce a sprite
  # that lags one build behind, so refuse to run before :elixir.
  defp order_error do
    compilers = Mix.Task.Compiler.compilers()
    iconex = Enum.find_index(compilers, &(&1 == :iconex))
    elixir = Enum.find_index(compilers, &(&1 == :elixir))

    if iconex && elixir && iconex < elixir do
      diagnostic(
        :error,
        "Iconex: the :iconex compiler must run after :elixir. " <>
          "In mix.exs, use: compilers: Mix.compilers() ++ [:iconex]",
        nil,
        0
      )
    end
  end

  defp fail(diagnostics) do
    Enum.each(diagnostics, &Code.print_diagnostic/1)
    {:error, diagnostics}
  end

  defp beam_stats do
    Mix.Project.compile_path()
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Map.new(&{&1, stat(&1)})
  end

  defp stat(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime, size: size}} -> {mtime, size}
      {:error, reason} -> reason
    end
  end

  # Returns [{set, name, file, line}] for the literal icon names a module uses.
  defp read_refs(path) do
    with {:ok, {module, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(String.to_charlist(path), [:debug_info]),
         {:ok, forms} <- backend.debug_info(:erlang_v1, module, data, []) do
      {_file, refs} = Enum.reduce(forms, {nil, []}, &collect_form/2)
      refs |> Enum.reverse() |> Enum.uniq()
    else
      _ -> {:skipped, "compiled without debug_info, so its icons cannot be detected"}
    end
  end

  defp collect_form({:attribute, _, :file, {file, _}}, {_file, refs}),
    do: {List.to_string(file), refs}

  defp collect_form(form, {file, refs}), do: {file, walk(form, file, refs)}

  # HEEx compiles every <Iconex.lucide ...> / <.lucide ...> to a call whose
  # arguments are a capture of Iconex.lucide/1 followed by the assigns map.
  defp walk(
         {:call, _, {:remote, _, {:atom, _, Iconex}, {:atom, _, :hint}}, [{:atom, _, set}, list]} =
           call,
         file,
         refs
       )
       when set in @set_ids do
    walk_children(call, file, literal_list(set, list, file) ++ refs)
  end

  defp walk({:call, _, _, args} = call, file, refs) do
    walk_children(call, file, icon_args(args, file) ++ refs)
  end

  defp walk(node, file, refs), do: walk_children(node, file, refs)

  defp walk_children(node, file, refs) when is_tuple(node) do
    node |> Tuple.to_list() |> walk_children(file, refs)
  end

  defp walk_children(nodes, file, refs) when is_list(nodes) do
    Enum.reduce(nodes, refs, &walk(&1, file, &2))
  end

  defp walk_children(_leaf, _file, refs), do: refs

  # Every known set is matched, enabled or not, so calls into a disabled set
  # are reported rather than silently ignored.
  defp icon_args(
         [
           {:fun, anno, {:function, {:atom, _, Iconex}, {:atom, _, set}, {:integer, _, 1}}},
           {:map, _, fields} | _
         ],
         file
       )
       when set in @set_ids do
    for {:map_field_assoc, _, {:atom, _, :name}, value} <- fields,
        name = literal_string(value),
        do: {set, name, file, :erl_anno.line(anno)}
  end

  defp icon_args([_ | rest], file), do: icon_args(rest, file)
  defp icon_args([], _file), do: []

  defp literal_list(set, {:cons, anno, head, tail}, file) do
    case literal_string(head) do
      nil -> literal_list(set, tail, file)
      name -> [{set, name, file, :erl_anno.line(anno)} | literal_list(set, tail, file)]
    end
  end

  defp literal_list(_set, _, _file), do: []

  defp literal_string({:bin, _, [{:bin_element, _, {:string, _, chars}, :default, :default}]}),
    do: List.to_string(chars)

  defp literal_string({:bin, _, []}), do: ""
  defp literal_string(_), do: nil

  defp disabled_set(set, file, line) do
    where = if file, do: "", else: " (referenced in config :iconex, #{set}: [extra_icons: ...])"

    diagnostic(
      :error,
      "Iconex: the #{set} icon set is not enabled. Add #{inspect(set)} to config :iconex, :sets" <>
        where,
      file,
      line
    )
  end

  defp unknown_icon(set, name, nil, _line) do
    diagnostic(
      :error,
      "Iconex: unknown #{set} icon #{inspect(name)} in config :iconex, #{set}: [extra_icons: ...]. " <>
        "Check the spelling against #{Iconex.Set.module!(set).docs_url()}",
      nil,
      0
    )
  end

  defp unknown_icon(set, name, file, line) do
    diagnostic(
      :error,
      "Iconex: unknown #{set} icon #{inspect(name)}. " <>
        "Check the spelling against #{Iconex.Set.module!(set).docs_url()}",
      file,
      line
    )
  end

  defp diagnostic(severity, message, file, line) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "iconex",
      severity: severity,
      message: message,
      file: file && Path.expand(file),
      source: file && Path.expand(file),
      position: line
    }
  end

  defp sprite_path do
    Path.expand(Application.get_env(:iconex, :output_path, @default_output))
  end

  defp manifest_path do
    Path.join(Mix.Project.manifest_path(), "#{@manifest_name}.manifest")
  end

  defp read_manifest do
    with {:ok, binary} <- File.read(manifest_path()),
         {@manifest_vsn, manifest} <- safe_binary_to_term(binary) do
      manifest
    else
      _ -> %{}
    end
  end

  defp safe_binary_to_term(binary) do
    :erlang.binary_to_term(binary)
  rescue
    ArgumentError -> nil
  end

  defp write_manifest(settings, beams, refs, icons) do
    manifest = %{settings: settings, beams: beams, refs: refs, icons: icons}
    File.mkdir_p!(Path.dirname(manifest_path()))
    File.write!(manifest_path(), :erlang.term_to_binary({@manifest_vsn, manifest}))
  end
end
