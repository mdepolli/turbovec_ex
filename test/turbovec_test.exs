defmodule TurboVecTest do
  use ExUnit.Case, async: true

  @u64_max 18_446_744_073_709_551_615

  describe "new/1" do
    test "returns a handle" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)

      assert is_reference(index)
    end

    test "accepts bit_width 2, 3, and 4" do
      # 3 is deliberately supported (spec)
      for bw <- [2, 3, 4] do
        assert {:ok, _} = TurboVec.new(dim: 8, bit_width: bw)
      end
    end

    test "rejects bit_width outside 2..4" do
      assert {:error, {:invalid_bit_width, 1}} = TurboVec.new(dim: 8, bit_width: 1)
      assert {:error, {:invalid_bit_width, 5}} = TurboVec.new(dim: 8, bit_width: 5)
    end

    test "rejects dim that is zero, not a multiple of 8, or too large" do
      assert {:error, {:invalid_dim, 0}} = TurboVec.new(dim: 0)
      assert {:error, {:invalid_dim, 7}} = TurboVec.new(dim: 7)
      assert {:error, {:dim_too_large, 16392, 16384}} = TurboVec.new(dim: 16392)
    end

    test "negative constructor integers raise" do
      # dim and bit_width are usize at the NIF boundary, so negatives fail
      # term decode and raise like any type error. (The id policy's
      # out-of-range tuples apply to ids only.)
      assert_raise ArgumentError, fn -> TurboVec.new(dim: -8) end
      assert_raise ArgumentError, fn -> TurboVec.new(dim: 8, bit_width: -1) end
    end
  end

  describe "add/3" do
    setup do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      %{index: index}
    end

    test "adds vectors and counts them" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      vectors = f32_binary([[1, 0, 0, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0, 0, 0]])

      assert :ok = TurboVec.add(index, vectors, [10, 20])
      assert TurboVec.count(index) == 2
    end

    test "rejects a buffer that is not a whole number of rows" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      # 9 floats over dim 8
      bin = f32_binary([List.duplicate(1.0, 9)])

      assert {:error, {:vector_buffer_size_mismatch, 9, 8}} = TurboVec.add(index, bin, [1])
    end

    test "rejects a buffer whose bytes are not whole f32s" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      # 33 bytes = one clean row plus a stray byte; without this check
      # the stray byte would be silently dropped and add succeed
      bin = f32_binary([List.duplicate(1.0, 8)]) <> <<0>>

      assert {:error, {:vector_byte_size_mismatch, 33}} = TurboVec.add(index, bin, [1])
    end

    test "rejects ids/vectors count mismatch" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      bin = f32_binary([List.duplicate(1.0, 8)])

      assert {:error, {:ids_count_mismatch, 1, 2}} = TurboVec.add(index, bin, [1, 2])
    end

    test "rejects an id already present and a duplicate in batch" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      row = f32_binary([List.duplicate(1.0, 8)])
      :ok = TurboVec.add(index, row, [7])

      # error atomicity: the failed batch adds nothing
      assert {:error, {:id_already_present, 7}} = TurboVec.add(index, row, [7])
      two = f32_binary([List.duplicate(1.0, 8), List.duplicate(2.0, 8)])
      assert {:error, {:duplicate_id_in_batch, 9}} = TurboVec.add(index, two, [9, 9])
      assert TurboVec.count(index) == 1
    end

    test "rejects non-finite input with row and coordinate" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      # NaN at row 0, coord 3 — value travels as a string (Erlang floats
      # can't hold NaN)
      nan = <<0, 0, 192, 127>>
      bin = f32_binary([[1.0, 1.0, 1.0]]) <> nan <> f32_binary([[1.0, 1.0, 1.0, 1.0]])

      assert {:error, {:invalid_input_value, 0, 3, value}} = TurboVec.add(index, bin, [1])
      assert is_binary(value)
    end

    test "rejects ids outside u64 at the source" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      bin = f32_binary([List.duplicate(1.0, 8)])

      assert {:error, {:id_out_of_range, _}} = TurboVec.add(index, bin, [@u64_max + 1])
      assert {:error, {:id_out_of_range, -1}} = TurboVec.add(index, bin, [-1])
    end

    test "raises ArgumentError for a non-integer id" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      bin = f32_binary([List.duplicate(1.0, 8)])

      # type errors raise; domain errors return tuples (spec).
      # 1.5 AND 1.0 are type errors, not :id_out_of_range.
      assert_raise ArgumentError, fn -> TurboVec.add(index, bin, [:seven]) end
      assert_raise ArgumentError, fn -> TurboVec.add(index, bin, [1.5]) end
      assert_raise ArgumentError, fn -> TurboVec.add(index, bin, [1.0]) end
      # beyond i128, the id value cannot ride in the error tuple
      assert_raise ArgumentError, fn -> TurboVec.add(index, bin, [Integer.pow(2, 200)]) end
    end

    test "raises ArgumentError for vectors that are neither binary nor tensor" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)

      # lists of floats are not an API; fail loudly, not with a FunctionClauseError
      assert_raise ArgumentError, fn -> TurboVec.add(index, [1.0, 2.0], [1]) end
    end

    @tag :nx
    test "adds an {n, dim} f32 tensor", %{index: index} do
      tensor = Nx.eye(8, type: {:f, 32})

      assert :ok = TurboVec.add(index, tensor, Enum.to_list(1..8))
      assert TurboVec.count(index) == 8
    end

    @tag :nx
    test "rejects non-f32 add tensors — byte size alone would misread f64", %{index: index} do
      tensor = Nx.broadcast(Nx.tensor(1.0, type: {:f, 64}), {2, 8})

      assert {:error, {:invalid_tensor_type, {:f, 64}}} = TurboVec.add(index, tensor, [1, 2])
    end

    @tag :nx
    test "rejects a transposed add tensor — same bytes, scrambled rows", %{index: index} do
      tensor = Nx.broadcast(Nx.tensor(1.0, type: {:f, 32}), {8, 2})

      assert {:error, {:invalid_tensor_shape, {8, 2}, 8}} = TurboVec.add(index, tensor, [1, 2])
    end
  end

  describe "remove/2" do
    setup do
      {:ok, index} = TurboVec.new(dim: 8)
      :ok = TurboVec.add(index, f32_binary([List.duplicate(1.0, 8)]), [42])
      %{index: index}
    end

    test "removes present ids and reports absent ones", %{index: index} do
      assert :ok = TurboVec.remove(index, 42)
      assert TurboVec.count(index) == 0
      assert {:error, :not_found} = TurboVec.remove(index, 42)
      assert {:error, {:id_out_of_range, _}} = TurboVec.remove(index, @u64_max + 1)
    end
  end

  describe "search/3" do
    setup do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      :ok = TurboVec.add(index, f32_binary(Enum.map(0..3, &basis/1)), [100, 101, 102, 103])
      %{index: index}
    end

    test "a stored vector's nearest neighbor is itself", %{index: index} do
      {:ok, results} = TurboVec.search(index, f32_binary([basis(2)]), k: 1)

      assert [{102, score}] = results
      assert is_float(score)
    end

    test "results are sorted best-first and length <= k", %{index: index} do
      # k beyond count clamps (spec: min(k, count, allowlist))
      {:ok, results} = TurboVec.search(index, f32_binary([basis(0)]), k: 10)

      assert length(results) == 4
      scores = Enum.map(results, &elem(&1, 1))
      assert scores == Enum.sort(scores, :desc)
    end

    test "empty index returns an empty list" do
      {:ok, empty} = TurboVec.new(dim: 8)

      assert {:ok, []} = TurboVec.search(empty, f32_binary([basis(0)]), k: 10)
    end

    test "k = 0 is rejected, not clamped", %{index: index} do
      assert {:error, {:invalid_k, 0}} = TurboVec.search(index, f32_binary([basis(0)]), k: 0)
    end

    test "a query that is not exactly one row is rejected", %{index: index} do
      # two rows would be a silent flattened batch (spec)
      two = f32_binary([basis(0), basis(1)])

      assert {:error, {:query_size_mismatch, 32, 64}} = TurboVec.search(index, two, k: 1)
      short = f32_binary([[1.0, 2.0]])
      assert {:error, {:query_size_mismatch, 32, 8}} = TurboVec.search(index, short, k: 1)
    end

    test "non-finite query coordinates are rejected", %{index: index} do
      # NaN at coord 5
      query =
        f32_binary([[1.0, 0.0, 0.0, 0.0, 0.0]]) <> <<0, 0, 192, 127>> <> f32_binary([[0.0, 0.0]])

      assert {:error, {:invalid_query_value, 5, value}} = TurboVec.search(index, query, k: 1)
      assert is_binary(value)
    end

    test "raises ArgumentError for a query that is neither binary nor tensor", %{index: index} do
      assert_raise ArgumentError, fn -> TurboVec.search(index, [1.0, 2.0], k: 1) end
    end

    test "allowlist restricts results and clamps k", %{index: index} do
      {:ok, results} =
        TurboVec.search(index, f32_binary([basis(0)]), k: 10, allowlist: [101, 103])

      # only allowed ids, clamped to allowlist size (spec)
      assert length(results) == 2
      assert Enum.map(results, &elem(&1, 0)) |> Enum.sort() == [101, 103]
    end

    test "empty allowlist is an error, not zero results", %{index: index} do
      # pass nil to search everything (upstream contract)
      assert {:error, :allowlist_empty} =
               TurboVec.search(index, f32_binary([basis(0)]), k: 1, allowlist: [])
    end

    test "unknown and out-of-range allowlist ids error", %{index: index} do
      query = f32_binary([basis(0)])

      assert {:error, {:unknown_id, 999}} = TurboVec.search(index, query, k: 1, allowlist: [999])

      assert {:error, {:id_out_of_range, _}} =
               TurboVec.search(index, query, k: 1, allowlist: [18_446_744_073_709_551_616])
    end

    @tag :nx
    test "searches with a {dim} tensor" do
      {:ok, index} = TurboVec.new(dim: 8)
      tensor = Nx.eye(8, type: {:f, 32})
      :ok = TurboVec.add(index, tensor, Enum.to_list(1..8))

      {:ok, [{3, _score} | _]} = TurboVec.search(index, Nx.take(tensor, Nx.tensor(2)), k: 1)
    end

    @tag :nx
    test "accepts a {1, dim} query as a courtesy" do
      {:ok, index} = TurboVec.new(dim: 8)
      :ok = TurboVec.add(index, Nx.eye(8, type: {:f, 32}), Enum.to_list(1..8))
      query = Nx.broadcast(Nx.tensor(1.0, type: {:f, 32}), {1, 8})

      assert {:ok, _} = TurboVec.search(index, query, k: 1)
    end

    @tag :nx
    test "rejects non-f32 query tensors — byte size alone would misread f64", %{index: index} do
      # f64 of dim/2 has exactly 4*dim bytes (spec adversarial case)
      query = Nx.broadcast(Nx.tensor(1.0, type: {:f, 64}), {4})

      assert {:error, {:invalid_tensor_type, {:f, 64}}} = TurboVec.search(index, query, k: 1)
    end

    @tag :nx
    test "rejects wrong-rank or wrong-dim queries", %{index: index} do
      two_row = Nx.broadcast(Nx.tensor(1.0, type: {:f, 32}), {2, 8})
      wrong_dim = Nx.broadcast(Nx.tensor(1.0, type: {:f, 32}), {16})

      assert {:error, {:invalid_tensor_shape, {2, 8}, 8}} = TurboVec.search(index, two_row, k: 1)
      assert {:error, {:invalid_tensor_shape, {16}, 8}} = TurboVec.search(index, wrong_dim, k: 1)
    end
  end

  describe "contains?/2" do
    setup do
      {:ok, index} = TurboVec.new(dim: 8)
      :ok = TurboVec.add(index, f32_binary([List.duplicate(1.0, 8)]), [42])
      %{index: index}
    end

    test "is a bare predicate", %{index: index} do
      # out-of-range id is false, not an error (spec deviation)
      assert TurboVec.contains?(index, 42)
      refute TurboVec.contains?(index, 43)
      refute TurboVec.contains?(index, @u64_max + 1)
      assert_raise ArgumentError, fn -> TurboVec.contains?(index, :nope) end
    end
  end

  describe "count/1" do
    test "starts at zero" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)

      assert TurboVec.count(index) == 0
    end
  end

  describe "bit_width/1" do
    test "defaults to 4" do
      {:ok, index} = TurboVec.new(dim: 8)

      assert TurboVec.bit_width(index) == 4
    end
  end

  defp f32_binary(rows) do
    for row <- rows, x <- row, into: <<>>, do: <<x::float-32-native>>
  end

  defp basis(i), do: for(j <- 0..7, do: if(j == i, do: 1.0, else: 0.0))
end
