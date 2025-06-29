defmodule DummySupervisor do
  @moduledoc false

  use CircuitBreakerSupervisor

  @impl true
  def backoff(attempt), do: attempt

  @impl true
  def enabled?(_id), do: true
end
