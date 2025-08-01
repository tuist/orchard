defmodule Orchard.MixProject do
  use Mix.Project

  def project do
    [
      app: :orchard,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      compilers: [:ensure_priv_dir] ++ Mix.compilers(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto],
      mod: {Orchard.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:muontrap, "~> 1.5"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description() do
    "An Elixir package for managing Apple devices and simulators"
  end

  defp package() do
    [
      name: "orchard",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tuist/orchard"},
      maintainers: ["Tuist"],
      files: [
        "lib",
        "priv/axe/versions.json",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
        ".formatter.exs"
      ]
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "https://github.com/tuist/orchard",
      homepage_url: "https://github.com/tuist/orchard",
      authors: ["Tuist"],
      api_reference: true
    ]
  end

  defp aliases do
    [
      "orchard.download": ["run -e 'Orchard.Downloader.download()'"]
    ]
  end
end

defmodule Mix.Tasks.Compile.EnsurePrivDir do
  use Mix.Task.Compiler

  def run(_args) do
    priv_dir = Path.join(Mix.Project.app_path(), "priv")
    File.mkdir_p!(priv_dir)
    :ok
  end
end
