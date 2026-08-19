defmodule TurboVec.NewTest do
  use ExUnit.Case, async: true

  test "new/1 returns a handle and count/1 starts at zero" do
    # Act
    {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)

    # Assert
    assert TurboVec.count(index) == 0
  end

  test "accepts bit_width 2, 3, and 4" do
    # Act + Assert — 3 is deliberately supported (spec)
    for bw <- [2, 3, 4] do
      assert {:ok, _} = TurboVec.new(dim: 8, bit_width: bw)
    end
  end

  test "rejects bit_width outside 2..4" do
    # Act + Assert
    assert {:error, {:invalid_bit_width, 1}} = TurboVec.new(dim: 8, bit_width: 1)
    assert {:error, {:invalid_bit_width, 5}} = TurboVec.new(dim: 8, bit_width: 5)
  end

  test "rejects dim that is zero, not a multiple of 8, or too large" do
    # Act + Assert
    assert {:error, {:invalid_dim, 0}} = TurboVec.new(dim: 0)
    assert {:error, {:invalid_dim, 7}} = TurboVec.new(dim: 7)
    assert {:error, {:dim_too_large, 16392, 16384}} = TurboVec.new(dim: 16392)
  end

  test "negative constructor integers raise" do
    # Act + Assert — pinned: dim and bit_width are usize at the NIF
    # boundary, so negatives fail term decode and raise like any type
    # error. (The id policy's out-of-range tuples apply to ids only.)
    assert_raise ArgumentError, fn -> TurboVec.new(dim: -8) end
    assert_raise ArgumentError, fn -> TurboVec.new(dim: 8, bit_width: -1) end
  end

  test "bit_width defaults to 4" do
    # Arrange / Act
    {:ok, index} = TurboVec.new(dim: 8)

    # Assert
    assert TurboVec.bit_width(index) == 4
  end
end

