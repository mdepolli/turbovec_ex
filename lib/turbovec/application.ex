defmodule TurboVec.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Feeds tier 3 of the pool-size precedence; honors a user-tuned +SDcpu.
    :ok = TurboVec.NIF.init_pool(:erlang.system_info(:dirty_cpu_schedulers))
    Supervisor.start_link([], strategy: :one_for_one, name: TurboVec.Supervisor)
  end
end
