defmodule Mix.Tasks.Iconex.Download do
  @moduledoc """
  Downloads Lucide's `icon-nodes.json` from the `lucide-static` npm package.

      mix iconex.download [--version VERSION] [--output PATH]

  ## Options

    * `--version` - the `lucide-static` version to fetch. Defaults to the
      latest version published on npm.
    * `--output` - where to write the file. Defaults to
      `priv/icon-nodes.json` inside the iconex repository, or, in a host
      application, to `config :iconex, :icon_nodes_path` when set and
      `priv/iconex/icon-nodes.json` otherwise.

  ## Using newer icons in a host application

  Point iconex at the downloaded file in `config/config.exs` (the path must
  be absolute):

      config :iconex, icon_nodes_path: Path.expand("../priv/iconex/icon-nodes.json", __DIR__)

  then recompile the dependency with `mix deps.compile iconex --force`. Once
  the config is in place, this task recompiles iconex automatically after each
  download. The task never writes into `deps/iconex`.
  """

  use Mix.Task

  @shortdoc "Downloads Lucide icon-nodes.json"
  @requirements []

  @latest_url "https://registry.npmjs.org/lucide-static/latest"

  @impl true
  def run(args) do
    opts = OptionParser.parse!(args, strict: [version: :string, output: :string]) |> elem(0)
    maintainer? = Mix.Project.config()[:app] == :iconex

    version = opts[:version] || latest_version()
    out = output_path(opts[:output], maintainer?)

    url = "https://cdn.jsdelivr.net/npm/lucide-static@#{version}/icon-nodes.json"

    body =
      case fetch(url, 60_000) do
        {:ok, body} -> body
        other -> Mix.raise("Iconex: failed to download #{url}: #{inspect(other)}")
      end

    icons =
      case JSON.decode(body) do
        {:ok, %{} = map} when map_size(map) > 0 ->
          if Enum.all?(map, fn {_name, nodes} -> is_list(nodes) end), do: map, else: invalid!()

        _ ->
          invalid!()
      end

    tmp = out <> ".tmp"
    File.mkdir_p!(Path.dirname(out))
    File.write!(tmp, body)
    File.rename!(tmp, out)

    Mix.shell().info(
      "Iconex: downloaded lucide-static #{version} (#{map_size(icons)} icons) to #{Path.relative_to_cwd(out)}"
    )

    unless maintainer?, do: host_follow_up(out)
  end

  defp latest_version do
    with {:ok, body} <- fetch(@latest_url, 30_000),
         {:ok, %{"version" => version}} when is_binary(version) <- JSON.decode(body) do
      version
    else
      reason ->
        Mix.raise("Iconex: could not resolve latest lucide-static version: #{inspect(reason)}")
    end
  end

  # Elixir < 1.19 refuses URLs without a checksum unless :unsafe_uri is set;
  # later versions ignore the option. TLS peer verification is on either way,
  # and the payload is validated before anything is written.
  defp fetch(url, timeout), do: Mix.Utils.read_path(url, timeout: timeout, unsafe_uri: true)

  defp output_path(output, _maintainer?) when is_binary(output), do: Path.expand(output)
  defp output_path(nil, true), do: Path.expand("priv/icon-nodes.json")

  defp output_path(nil, false) do
    case Application.get_env(:iconex, :icon_nodes_path) do
      nil ->
        Path.expand("priv/iconex/icon-nodes.json")

      path when is_binary(path) ->
        if Path.type(path) == :absolute do
          path
        else
          Mix.raise(
            "config :iconex, :icon_nodes_path must be an absolute path, got: #{inspect(path)}. " <>
              ~s|Use Path.expand("../priv/iconex/icon-nodes.json", __DIR__) in config/config.exs.|
          )
        end
    end
  end

  defp host_follow_up(out) do
    if Application.get_env(:iconex, :icon_nodes_path) == out do
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
          config :iconex, icon_nodes_path: Path.expand("../#{Path.relative_to_cwd(out)}", __DIR__)
      then run: mix deps.compile iconex --force\
      """)
    end
  end

  defp invalid!, do: Mix.raise("Iconex: downloaded data is not a valid icon-nodes map")
end
