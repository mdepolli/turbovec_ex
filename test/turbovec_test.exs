defmodule TurboVecTest do
  use ExUnit.Case, async: true

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

  describe "add/3" do
    test "adds vectors and counts them" do
      {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)
      vectors = f32_binary([[1, 0, 0, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0, 0, 0]])

      assert :ok = TurboVec.add(index, vectors, [10, 20])
      assert TurboVec.count(index) == 2
    end
  end

  defp f32_binary(rows) do
    for row <- rows, x <- row, into: <<>>, do: <<x::float-32-native>>
  end
end

