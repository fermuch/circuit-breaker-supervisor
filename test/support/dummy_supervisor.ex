defmodule DummySupervisor do
  @moduledoc false

  use CircuitBreakerSupervisor

  @impl true
  def backoff(_attempt), do: 0

  @impl true
  def enabled?(id), do: DummyFeatureFlagService.enabled?(id)
end
