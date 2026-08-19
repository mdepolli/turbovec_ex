defmodule TurboVec.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mdepolli/turbovec_ex"

  def project do
    [
      app: :turbovec_ex,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "TurboVec",
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {TurboVec.Application, []}
    ]
  end

  defp deps do
    [
      # NIF
      {:rustler, "~> 0.36"},

      # Dev/Test
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ] ++ nx_dep()
  end

  # NO_NX=1 excludes Nx so CI can prove the library compiles without it.
  defp nx_dep do
    if System.get_env("NO_NX"), do: [], else: [{:nx, "~> 0.9", optional: true}]
  end

  defp description do
    """
    In-process vector search via the turbovec Rust crate. TurboQuant 2–4-bit
    compression, SIMD scoring, stable u64 ids. 64-bit only.
    """
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Marcelo De Polli"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md"
      ]
    ]
  end
end
