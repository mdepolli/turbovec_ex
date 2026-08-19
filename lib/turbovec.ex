defmodule TurboVec do
  @moduledoc """
  In-process vector search over the turbovec Rust crate (`IdMapIndex`).

  The index handle is a node-local NIF resource: it cannot cross nodes,
  survive `:erlang.term_to_binary/1`, or live in ETS across restarts.
  Move an index between nodes or lifetimes with `write/2` and `load/1`.
  """

  alias TurboVec.NIF

  @type index :: reference()

  @doc """
  Creates an index. `dim` is required (positive multiple of 8, ≤ 16384);
  `bit_width` is 2, 3, or 4 (default 4).
  """
  @spec new(keyword()) :: {:ok, index()} | {:error, term()}
  def new(opts) do
    dim = Keyword.fetch!(opts, :dim)
    bit_width = Keyword.get(opts, :bit_width, 4)

    case NIF.new(dim, bit_width) do
      {:error, _} = error -> error
      index -> {:ok, index}
    end
  end

  @doc "Number of vectors in the index. Infallible."
  @spec count(index()) :: non_neg_integer()
  def count(index), do: NIF.count(index)
end
