defmodule CircuitBreakerSupervisor.State do
  @moduledoc """
  Finite state machine for tracking status of a single supervised process.

  Allowed states are:

  - running_disabled (feature flag turned off, should not be running)
  - running_in_startup (process is running, but hasn't been running long enough to be considered fixed)
  - running_past_startup (process is running, and we can reset the attempt counter because it has recovered)
  - stopped_disabled (feature flag turned off, should not be restarted)
  - stopped_in_backoff (process crashed, but we need to wait before retrying it)
  - stopped_past_backoff (process crashed and is ready to be retried)
  """

  alias CircuitBreakerSupervisor.Monitor

  defstruct attempt_count: 0,
            started_at: nil,
            stopped_at: nil

  def running?(%Monitor{supervisor: supervisor}, id) do
    case id_to_pid(supervisor, id) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

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
