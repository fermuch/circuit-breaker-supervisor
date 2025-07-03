defmodule CircuitBreakerSupervisorTest do
  use ExUnit.Case

  setup do
    start_supervised!(DummyFeatureFlagService)
    :ok
  end

  test "starts supervised children" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    start_supervised!({DummySupervisor, children: children})
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  test "only starts enabled children" do
    # mark child disabled before startup
    DummyFeatureFlagService.disable(:disable_me)
    children = [sleepy_worker(id: :one), sleepy_worker(id: :disable_me)]
    start_supervised!({DummySupervisor, children: children})
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  test "starts child that was enabled after startup" do
    # mark child disabled before startup
    DummyFeatureFlagService.disable(:enable_me)
    children = [sleepy_worker(id: :enable_me)]
    start_supervised!({DummySupervisor, children: children})
    assert %{active: 0} = Supervisor.count_children(DummySupervisor.Supervisor)

    # enable child and verify that it is started
    DummyFeatureFlagService.enable(:enable_me)
    send(CircuitBreakerSupervisor.Monitor, :check_children)
    Process.sleep(100)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  test "terminates disabled children" do
    # startup with child enabled
    children = [sleepy_worker(id: :one), sleepy_worker(id: :disable_me)]
    start_supervised!({DummySupervisor, children: children})
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)

    # disable child and verify that it is terminated
    DummyFeatureFlagService.disable(:disable_me)
    send(CircuitBreakerSupervisor.Monitor, :check_children)
    Process.sleep(100)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  test "restarts crashed child" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    start_supervised!({DummySupervisor, children: children})

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
