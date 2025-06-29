defmodule CircuitBreakerSupervisorTest do
  use ExUnit.Case
  doctest CircuitBreakerSupervisor

  test "starts supervised children" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    {:ok, _pid} = start_supervised({CircuitBreakerSupervisor, children: children})
    assert %{active: 2} = Supervisor.count_children(CircuitBreakerSupervisor.Supervisor)
  end

  defp sleepy_worker(opts) do
    mfa = {Task, :start_link, [Process, :sleep, [:infinity]]}
    Supervisor.child_spec(%{id: Task, start: mfa}, opts)
  end
end
