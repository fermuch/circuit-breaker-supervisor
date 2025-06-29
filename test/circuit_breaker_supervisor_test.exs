defmodule CircuitBreakerSupervisorTest do
  use ExUnit.Case

  test "starts supervised children" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    {:ok, _pid} = start_supervised({DummySupervisor, children: children})
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  test "restarts crashed child" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    {:ok, _pid} = start_supervised({DummySupervisor, children: children})

    # kill child
    :ok = Supervisor.terminate_child(DummySupervisor.Supervisor, :one)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)

    # wait for it to be restarted, should be restarted right away without
    # waiting for `check_children` to be called
    Process.sleep(100)
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  defp sleepy_worker(opts) do
    mfa = {Task, :start_link, [Process, :sleep, [:infinity]]}
    Supervisor.child_spec(%{id: Task, start: mfa}, opts)
  end
end
