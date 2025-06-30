defmodule DummySupervisor do
  @moduledoc false

  use CircuitBreakerSupervisor

  @impl true
  def backoff(attempt), do: attempt

  @impl true
  def enabled?(:disable_me), do: false
  def enabled?(_id), do: true
end
