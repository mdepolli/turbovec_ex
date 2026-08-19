defmodule TurboVec do
  @moduledoc """
  In-process vector search over the turbovec Rust crate (`IdMapIndex`).

  The index handle is a node-local NIF resource: it cannot cross nodes,
  survive `:erlang.term_to_binary/1`, or live in ETS across restarts.
  Move an index between nodes or lifetimes with `write/2` and `load/1`.
  """

  alias TurboVec.NIF

  @type index :: reference()

  @typedoc "A native-endian f32 binary, or (with Nx) an `Nx.Tensor` of type {:f, 32}."
  @type vector_input :: binary() | struct()

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

  @doc """
  Adds vectors with stable u64 ids. Error atomicity: a rejected batch
  leaves the index exactly as it was — no cleanup needed.
  """
  @spec add(index(), vector_input(), [non_neg_integer()]) :: :ok | {:error, term()}
  def add(index, vectors, ids) when is_binary(vectors), do: NIF.add(index, vectors, ids)

  def add(_index, vectors, _ids) do
    raise ArgumentError,
          "vectors must be a native-endian f32 binary or an Nx.Tensor, got: #{inspect(vectors)}"
  end

  @doc """
  Top-k search. Returns up to `k` results — `k` is clamped to the index
  (and allowlist) size, so `length(results) <= k`; an empty index returns
  `{:ok, []}`. Scores are length-renormalized inner product, equal to
  cosine only for L2-normalized vectors.
  """
  @spec search(index(), vector_input(), keyword()) ::
          {:ok, [{non_neg_integer(), float()}]} | {:error, term()}
  def search(index, query, opts) do
    k = Keyword.fetch!(opts, :k)
    allowlist = Keyword.get(opts, :allowlist)

    with {:ok, binary} <- query_binary(query, index) do
      case NIF.search(index, binary, k, allowlist) do
        {:error, _} = error -> error
        results -> {:ok, results}
      end
    end
  end

  @doc "Number of vectors in the index. Infallible."
  @spec count(index()) :: non_neg_integer()
  def count(index), do: NIF.count(index)

  @doc "Vector dimensionality. Infallible; always committed."
  @spec dim(index()) :: pos_integer()
  def dim(index), do: NIF.dim(index)

  @doc "Bits per coordinate (2, 3, or 4). Infallible."
  @spec bit_width(index()) :: 2 | 3 | 4
  def bit_width(index), do: NIF.bit_width(index)

  defp query_binary(query, _index) when is_binary(query), do: {:ok, query}

  defp query_binary(query, _index) do
    raise ArgumentError,
          "query must be a native-endian f32 binary or an Nx.Tensor, got: #{inspect(query)}"
  end
end
