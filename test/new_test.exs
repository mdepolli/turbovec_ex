defmodule TurboVec.NewTest do
  use ExUnit.Case, async: true

  test "new/1 returns a handle and count/1 starts at zero" do
    # Act
    {:ok, index} = TurboVec.new(dim: 8, bit_width: 4)

    # Assert
    assert TurboVec.count(index) == 0
  end
end
