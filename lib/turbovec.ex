defmodule TurboVec do
  @moduledoc """
  In-process vector search over the turbovec Rust crate (`IdMapIndex`).

  The index handle is a node-local NIF resource: it cannot cross nodes,
  survive `:erlang.term_to_binary/1`, or live in ETS across restarts.
  Move an index between nodes or lifetimes with `write/2` and `load/1`.
  """

  import Bitwise

  alias TurboVec.NIF

  @compile {:no_warn_undefined, {Nx, :to_binary, 1}}

  @u64_max (1 <<< 64) - 1

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
  Loads a `write/2` snapshot or a `sync/2` container. Corruption and
  foreign-writer conflicts both surface as `{:io_error, :invalid_data, msg}`
  — distinguishable only by message (upstream limitation).
  """
  @spec load(Path.t()) :: {:ok, index()} | {:error, term()}
  def load(path) do
    case NIF.load(IO.chardata_to_string(path)) do
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

  def add(index, %_{} = tensor, ids) do
    with {:ok, binary} <- tensor_binary(tensor, {:add, dim(index)}) do
      NIF.add(index, binary, ids)
    end
  end

  def add(_index, vectors, _ids) do
    raise ArgumentError,
          "vectors must be a native-endian f32 binary or an Nx.Tensor, got: #{inspect(vectors)}"
  end

  @doc "Removes one id. `{:error, :not_found}` if absent."
  @spec remove(index(), non_neg_integer()) :: :ok | {:error, term()}
  def remove(index, id), do: NIF.remove(index, id)

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

  @doc """
  Whether `id` is in the index. Bare boolean — the one deliberate break
  from ok/error tuples. An integer outside u64 returns `false`: it cannot
  be present. The first id lookup after `load/1` builds the id map, O(n).
  """
  @spec contains?(index(), integer()) :: boolean()
  def contains?(index, id) when is_integer(id) and id >= 0 and id <= @u64_max,
    do: NIF.contains(index, id)

  def contains?(_index, id) when is_integer(id), do: false

  def contains?(_index, id),
    do: raise(ArgumentError, "id must be an integer, got: #{inspect(id)}")

  @doc "Number of vectors in the index. Infallible."
  @spec count(index()) :: non_neg_integer()
  def count(index), do: NIF.count(index)

  @doc "Vector dimensionality. Infallible; always committed."
  @spec dim(index()) :: pos_integer()
  def dim(index), do: NIF.dim(index)

  @doc "Bits per coordinate (2, 3, or 4). Infallible."
  @spec bit_width(index()) :: 2 | 3 | 4
  def bit_width(index), do: NIF.bit_width(index)

  @doc """
  Full durable snapshot (atomic replace). `write` then `sync` on the
  same path rebuilds (the snapshot is unclaimed, not foreign). Two
  handles incrementally syncing one path is not supported — the lagging
  handle fails at its next `sync`.
  Holding the read lock: mutations queue for the duration, and once one
  queues, new searches may block behind it (no RwLock fairness is
  guaranteed). Prefer `sync/2` for routine durability; call `write/2`
  in quiet periods.
  """
  @spec write(index(), Path.t()) :: :ok | {:error, term()}
  def write(index, path), do: NIF.write_index(index, IO.chardata_to_string(path))

  @doc """
  Durable incremental save. First call to a fresh path writes the whole
  file; the index stays bound to the path. One writer per path — a
  concurrent writer is detected at the *next* sync, not locked out.
  """
  @spec sync(index(), Path.t()) :: :ok | {:error, term()}
  def sync(index, path), do: NIF.sync(index, IO.chardata_to_string(path))

  defp query_binary(query, _index) when is_binary(query), do: {:ok, query}

  defp query_binary(%_{} = tensor, index), do: tensor_binary(tensor, {:query, dim(index)})

  defp query_binary(query, _index) do
    raise ArgumentError,
          "query must be a native-endian f32 binary or an Nx.Tensor, got: #{inspect(query)}"
  end

  # Runtime dispatch: a live Nx.Tensor struct means Nx is loaded — no
  # function_exported? probe, no conditional module (spec).
  defp tensor_binary(tensor, shape_rule) do
    cond do
      not is_struct(tensor, Nx.Tensor) ->
        raise ArgumentError, "expected a binary or Nx.Tensor, got: #{inspect(tensor)}"

      tensor.type != {:f, 32} ->
        {:error, {:invalid_tensor_type, tensor.type}}

      not shape_ok?(tensor.shape, shape_rule) ->
        {:error, {:invalid_tensor_shape, tensor.shape, elem(shape_rule, 1)}}

      true ->
        {:ok, Nx.to_binary(tensor)}
    end
  end

  defp shape_ok?({_n, dim}, {:add, dim}), do: true
  defp shape_ok?({dim}, {:query, dim}), do: true
  defp shape_ok?({1, dim}, {:query, dim}), do: true
  defp shape_ok?(_shape, _rule), do: false
end
