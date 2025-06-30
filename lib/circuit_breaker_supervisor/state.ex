defmodule CircuitBreakerSupervisor.State do
  @moduledoc """
  Finite state machine for tracking status of a single supervised process.

  Allowed states are:

  - running_disabled (feature flag turned off, should not be running)
  - running_in_startup (process is running, but hasn't been running long enough to be considered fixed)
  - running_past_startup (process is running, and we can reset the attempt counter because it has recovered)
  - stopped_disabled (feature flag turned off, should not be restarted)
  - stopped_in_backoff (process crashed, but we need to wait before retrying it)
  - stopped_past_backoff (process crashed and is ready to be retried, or hasn't been started)
  """

  alias CircuitBreakerSupervisor.Monitor
  alias CircuitBreakerSupervisor.State

  defstruct attempt_count: -1,
            backoff_time: 0,
            spec: nil,
            started_at: nil,
            status: :stopped_past_backoff,
            stopped_at: nil

  # recompute state for the process and return it
  def get_state(
        %Monitor{
          child_startup_time: startup_time,
          children: children,
          enabled?: enabled?,
          supervisor: supervisor
        } = monitor_state,
        id
      ) do
    state = Map.fetch!(children, id)
    enabled = enabled?.(id)
    running = running?(supervisor, id)

    cond do
      running and not enabled ->
        %{state | status: :running_disabled}

      running and enabled ->
        state =
          if is_nil(state.started_at) do
            # if we just started, then set started_at and clear stopped_at
            record_start(state)
          else
            state
          end

        # after a process has been running for long enough, past failures
        # shouldn't matter. reset the attempt count to 0
        if now() >= state.started_at + startup_time do
          %{state | attempt_count: 0, status: :running_past_startup}
        else
          %{state | status: :running_in_startup}
        end

      not running and not enabled ->
        %{state | status: :stopped_disabled}

      not running and enabled ->
        state =
          if is_nil(state.stopped_at) do
            # if we just crashed, then set stopped_at, compute backoff_time,
            # and increment attempt_count
            record_stop(monitor_state, state)
          else
            state
          end

        if now() >= state.stopped_at + state.backoff_time do
          %{state | status: :stopped_past_backoff}
        else
          %{state | status: :stopped_in_backoff}
        end
    end
  end

  defp running?(supervisor, id) do
    case id_to_pid(supervisor, id) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  defp record_start(%State{} = state) do
    %{state | backoff_time: nil, started_at: now(), stopped_at: nil}
  end

  defp record_stop(%Monitor{backoff: backoff}, %State{attempt_count: attempt_count} = state) do
    attempt_count = attempt_count + 1

    %{
      state
      | attempt_count: attempt_count,
        backoff_time: backoff.(attempt_count),
        started_at: nil,
        stopped_at: now()
    }
  end

  defp now, do: System.monotonic_time(:millisecond)

  @spec id_to_pid(Supervisor.supervisor(), atom()) :: pid()
  defp id_to_pid(supervisor, id) do
    Supervisor.which_children(supervisor)
    |> Enum.find(fn
      {^id, _, _, _} -> true
      _ -> false
    end)
    |> case do
      {_, pid, _, _} -> pid
      _ -> nil
    end
  end
end
