defmodule TurboVec.NIF do
  @moduledoc false

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :turbovec_ex,
    crate: "turbovec_nif",
    base_url: "https://github.com/mdepolli/turbovec_ex/releases/download/v#{version}",
    version: version,
    nif_versions: ["2.15"],
    targets: [
      "aarch64-apple-darwin",
      "x86_64-apple-darwin",
      "aarch64-unknown-linux-gnu",
      "aarch64-unknown-linux-musl",
      "x86_64-unknown-linux-gnu",
      "x86_64-unknown-linux-musl",
      "x86_64-pc-windows-msvc"
    ],
    # Mix.env() == :test is only :test when developing turbovec_ex itself
    # (deps compile as :prod in host projects), so `mix test` keeps working
    # here without env vars — and users are never forced to build from source.
    force_build: System.get_env("TURBOVEC_EX_BUILD") in ["1", "true"] or Mix.env() == :test

  def new(_dim, _bit_width), do: err()
  def load(_path), do: err()
  def add(_index, _vectors, _ids), do: err()
  def remove(_index, _id), do: err()
  def search(_index, _query, _k, _allowlist), do: err()
  def contains(_index, _id), do: err()
  def count(_index), do: err()
  def dim(_index), do: err()
  def bit_width(_index), do: err()
  def write_index(_index, _path), do: err()
  def sync(_index, _path), do: err()

  defp err, do: :erlang.nif_error(:nif_not_loaded)
end
