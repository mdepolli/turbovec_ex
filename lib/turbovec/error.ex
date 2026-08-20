defmodule TurboVec.Error do
  @moduledoc """
  Raised by bang functions (`new!/1`, `load!/1`). `reason` is the same
  term the non-bang function would return as `{:error, reason}`.
  """

  defexception [:reason]

  @impl true
  def message(%{reason: reason}) do
    "TurboVec failed: #{inspect(reason)}"
  end
end
