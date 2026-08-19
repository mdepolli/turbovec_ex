unless Code.ensure_loaded?(Nx) do
  ExUnit.configure(exclude: [:nx])
end

ExUnit.start()
