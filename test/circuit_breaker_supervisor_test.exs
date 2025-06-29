defmodule CircuitBreakerSupervisorTest do
  use ExUnit.Case
  doctest CircuitBreakerSupervisor

  test "starts supervised children" do
    {:ok, _pid} = start_supervised({CircuitBreakerSupervisor, children: [sleepy_worker()]})
    assert %{active: 1} = Supervisor.count_children(CircuitBreakerSupervisor.Supervisor)
  end

  defp sleepy_worker(opts \\ []) do
    mfa = {Task, :start_link, [Process, :sleep, [:infinity]]}
    Supervisor.child_spec(%{id: Task, start: mfa}, opts)
  end
end
