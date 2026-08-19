defmodule TurboVec.NIF do
  @moduledoc false
  use Rustler, otp_app: :turbovec_ex, crate: "turbovec_nif"

  def new(_dim, _bit_width), do: err()
  def count(_index), do: err()
  def bit_width(_index), do: err()
  def dim(_index), do: err()
  def add(_index, _vectors, _ids), do: err()

  defp err, do: :erlang.nif_error(:nif_not_loaded)
end
