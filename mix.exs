defmodule Iconex.MixProject do
  use Mix.Project

  @source "https://github.com/paradox460/iconex"
  # Icon set releases bundled into the Hex package. priv/sets/ is not in git;
  # the hex.build/hex.publish aliases download these versions first.
  @set_versions [lucide: "1.47.0"]

  def project do
    [
      app: :iconex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Lucide Icons as SVG sprites, with tree-shaking",
      package: package(),
      docs: [main: "Iconex", source_url: @source],
      aliases: aliases()
    ]
  end

  defp aliases do
    # A separate VM: compiling in-process (needed to load the task) breaks
    # Hex's module loading for the hex.build/hex.publish that follows.
    fetch = for {set, v} <- @set_versions, do: "cmd mix iconex.download #{set} --version #{v}"
    ["hex.build": fetch ++ ["hex.build"], "hex.publish": fetch ++ ["hex.publish"]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Upper bound prevents from potentially breaking changes to undocumented apis
      {:phoenix_live_view, ">= 0.18.0 and < 2.0.0"},
      {:igniter, "~> 0.8", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source},
      # Make sure the vendored icon data ships with the package
      files: ~w[lib priv/sets mix.exs README.md LICENSE]
    ]
  end
end
