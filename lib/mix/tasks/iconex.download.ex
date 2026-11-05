defmodule Mix.Tasks.Iconex.Download do
  @moduledoc """
  Downloads an icon set's data from npm and writes it in iconex's format.

      mix iconex.download SET [--version VERSION] [--output PATH]

  `SET` is one of the ids in `Iconex.Set.ids/0`, such as `lucide`.

  ## Options

    * `--version` - the version of the set's npm package to fetch (see
      `Iconex.Set`). Defaults to the latest version published on npm.
    * `--output` - where to write the file. Defaults to `priv/sets/SET.json`
      inside the iconex repository, or, in a host application, to
      `config :iconex, SET: [data_path: ...]` when set and
      `priv/iconex/SET.json` otherwise.

  ## Using newer icons in a host application

  Point iconex at the downloaded file in `config/config.exs` (the path must
  be absolute):

      config :iconex, lucide: [data_path: Path.expand("../priv/iconex/lucide.json", __DIR__)]

  then recompile the dependency with `mix deps.compile iconex --force`. Once
  the config is in place, this task recompiles iconex automatically after each
  download. The task never writes into `deps/iconex`.
  """

  use Mix.Task

  @shortdoc "Downloads an icon set's data"
  @requirements []

  @impl true
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: [version: :string, output: :string])
    set = parse_set(positional)
    mod = Iconex.Set.module!(set)
    maintainer? = Mix.Project.config()[:app] == :iconex

    version = opts[:version] || latest_version(mod.npm_package())
    out = output_path(set, opts[:output], maintainer?)
    url = mod.data_url(version)

    body =
      case fetch(url, 120_000) do
        {:ok, body} -> body
        other -> Mix.raise("Iconex: failed to download #{url}: #{inspect(other)}")
      end

    icons =
      with {:ok, decoded} <- JSON.decode(body),
           {:ok, icons} <- mod.normalize(decoded) do
        icons
      else
        _ -> Mix.raise("Iconex: downloaded #{set} data is not valid")
      end

    tmp = out <> ".tmp"
    File.mkdir_p!(Path.dirname(out))

    File.write!(
      tmp,
      JSON.encode!(%{"set" => to_string(set), "version" => version, "icons" => icons})
    )

    File.rename!(tmp, out)

    Mix.shell().info(
      "Iconex: downloaded #{mod.npm_package()} #{version} (#{map_size(icons)} icons) to #{Path.relative_to_cwd(out)}"
    )

    unless maintainer?, do: host_follow_up(set, out)
  end

  defp parse_set([name]) do
    Enum.find(Iconex.Set.ids(), &(Atom.to_string(&1) == name)) || usage!()
  end

  defp parse_set(_), do: usage!()

  defp usage! do
    Mix.raise(
      "Usage: mix iconex.download SET [--version VERSION] [--output PATH], where SET is one of: " <>
        Enum.join(Iconex.Set.ids(), ", ")
    )
  end

  defp latest_version(package) do
    with {:ok, body} <- fetch("https://registry.npmjs.org/#{package}/latest", 30_000),
         {:ok, %{"version" => version}} when is_binary(version) <- JSON.decode(body) do
      version
    else
      reason ->
        Mix.raise("Iconex: could not resolve latest #{package} version: #{inspect(reason)}")
    end
  end

  # Elixir < 1.19 refuses URLs without a checksum unless :unsafe_uri is set;
  # later versions ignore the option. TLS peer verification is on either way,
  # and the payload is validated before anything is written.
  defp fetch(url, timeout), do: Mix.Utils.read_path(url, timeout: timeout, unsafe_uri: true)

  defp output_path(_set, output, _maintainer?) when is_binary(output), do: Path.expand(output)
  defp output_path(set, nil, true), do: Path.expand("priv/sets/#{set}.json")

  defp output_path(set, nil, false) do
    case configured_path(set) do
      nil ->
        Path.expand("priv/iconex/#{set}.json")

      path when is_binary(path) ->
        if Path.type(path) == :absolute do
          path
        else
          Mix.raise(
            "config :iconex, #{set}: [data_path: ...] must be an absolute path, got: #{inspect(path)}. " <>
              ~s|Use Path.expand("../priv/iconex/#{set}.json", __DIR__) in config/config.exs.|
          )
        end
    end
  end

  defp configured_path(set), do: Application.get_env(:iconex, set, [])[:data_path]

  defp host_follow_up(set, out) do
    if configured_path(set) == out do
      # @external_resource is not watched for Hex deps, so force the recompile.
      # This must run in a fresh VM: Mix has already run `compile` for path deps
      # during this session, so an in-process `deps.compile --force` would wipe
      # the dep's build directory without rebuilding it.
      status =
        Mix.shell().cmd("mix deps.compile iconex --force",
          env: [{"MIX_ENV", Atom.to_string(Mix.env())}]
        )

      status == 0 ||
        Mix.raise("Iconex: `mix deps.compile iconex --force` exited with status #{status}")
    else
      Mix.shell().info("""
      Iconex: to use this file, add to config/config.exs:
          config :iconex, #{set}: [data_path: Path.expand("../#{Path.relative_to_cwd(out)}", __DIR__)]
      then run: mix deps.compile iconex --force\
      """)
    end
  end
end
