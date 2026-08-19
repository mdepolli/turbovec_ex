defmodule TurboVec.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Feeds tier 3 of the pool-size precedence; honors a user-tuned +SDcpu.
    :ok = TurboVec.NIF.init_pool(:erlang.system_info(:dirty_cpu_schedulers))
    # OTP requires a root pid; this is not an ownership process.
    {:ok, spawn_link(fn -> Process.sleep(:infinity) end)}
  end
end
