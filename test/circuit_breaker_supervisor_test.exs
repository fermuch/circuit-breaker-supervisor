defmodule CircuitBreakerSupervisorTest do
  use ExUnit.Case
  doctest CircuitBreakerSupervisor

  test "greets the world" do
    assert CircuitBreakerSupervisor.hello() == :world
  end
end
