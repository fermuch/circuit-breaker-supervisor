defmodule CircuitBreakerSupervisorTest do
  use ExUnit.Case

  import TelemetryTest

  setup [:telemetry_listen]

  setup do
    start_supervised!(DummyFeatureFlagService)
    :ok
  end

  @tag telemetry_listen: [:circuit_breaker_supervisor, :child, :start]
  test "starts supervised children" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    start_supervised!({DummySupervisor, children: children})
    assert_telemetry_start(:one, 0)
    assert_telemetry_start(:two, 0)
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  @tag telemetry_listen: [:circuit_breaker_supervisor, :child, :start]
  test "only starts enabled children" do
    # mark child disabled before startup
    DummyFeatureFlagService.disable(:disable_me)
    children = [sleepy_worker(id: :one), sleepy_worker(id: :disable_me)]
    start_supervised!({DummySupervisor, children: children})
    assert_telemetry_start(:one, 0)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  @tag telemetry_listen: [:circuit_breaker_supervisor, :child, :start]
  test "starts child that was enabled after startup" do
    # mark child disabled before startup
    DummyFeatureFlagService.disable(:enable_me)
    children = [sleepy_worker(id: :enable_me)]
    start_supervised!({DummySupervisor, children: children})
    assert %{active: 0} = Supervisor.count_children(DummySupervisor.Supervisor)

    # enable child and verify that it is started
    DummyFeatureFlagService.enable(:enable_me)
    send(CircuitBreakerSupervisor.Monitor, :check_children)
    assert_telemetry_start(:enable_me, 0)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  @tag telemetry_listen: [
         [:circuit_breaker_supervisor, :child, :start],
         [:circuit_breaker_supervisor, :child, :stop]
       ]
  test "terminates disabled children" do
    # startup with child enabled
    children = [sleepy_worker(id: :one), sleepy_worker(id: :disable_me)]
    start_supervised!({DummySupervisor, children: children})
    assert_telemetry_start(:one, 0)
    assert_telemetry_start(:disable_me, 0)
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)

    # disable child and verify that it is terminated
    DummyFeatureFlagService.disable(:disable_me)
    send(CircuitBreakerSupervisor.Monitor, :check_children)
    assert_telemetry_stop(:disable_me, 0)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  @tag telemetry_listen: [
         [:circuit_breaker_supervisor, :child, :start],
         [:circuit_breaker_supervisor, :child, :stop]
       ]
  test "restarts crashed child" do
    children = [sleepy_worker(id: :one), sleepy_worker(id: :two)]
    start_supervised!({DummySupervisor, children: children})
    assert_telemetry_start(:one, 0)
    assert_telemetry_start(:two, 0)
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)

    # kill child
    :ok = Supervisor.terminate_child(DummySupervisor.Supervisor, :one)
    assert_telemetry_stop(:one, 0)
    assert %{active: 1} = Supervisor.count_children(DummySupervisor.Supervisor)

    # wait for it to be restarted, should be restarted right away without
    # waiting for `check_children` to be called
    assert_telemetry_start(:one, 1)
    assert %{active: 2} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  @tag telemetry_listen: [:circuit_breaker_supervisor, :child, :stop]
  test "restarts child that crashes during startup" do
    children = [startup_crash_worker(id: :crash)]
    start_supervised!({DummySupervisor, children: children})

    # no start event because it never starts, only a stop
    assert_telemetry_stop(:crash, 0)

    # check_children should trigger a retry, since backoff is 0
    send(CircuitBreakerSupervisor.Monitor, :check_children)

    # attempt count should be incremented
    assert_telemetry_stop(:crash, 1)
    assert %{active: 0} = Supervisor.count_children(DummySupervisor.Supervisor)
  end

  defp sleepy_worker(opts) do
    mfa = {Task, :start_link, [Process, :sleep, [:infinity]]}
    Supervisor.child_spec(%{id: Task, start: mfa}, opts)
  end

  defp startup_crash_worker(opts) do
    # crashes on startup, because start_link is replaced with a fn that raises
    mfa = {__MODULE__, :crashing_start_link, []}
    Supervisor.child_spec(%{id: :crashing_worker, start: mfa}, opts)
  end

  def crash_start_link, do: raise("startup crash")

  defp assert_telemetry_start(id, attempt_count) do
    assert_receive {:telemetry_event,
                    %{
                      event: [:circuit_breaker_supervisor, :child, :start],
                      measurements: %{attempt_count: ^attempt_count},
                      metadata: %{id: ^id}
                    }}
  end

  defp assert_telemetry_stop(id, attempt_count) do
    assert_receive {:telemetry_event,
                    %{
                      event: [:circuit_breaker_supervisor, :child, :stop],
                      measurements: %{attempt_count: ^attempt_count},
                      metadata: %{id: ^id}
                    }}
  end
end
