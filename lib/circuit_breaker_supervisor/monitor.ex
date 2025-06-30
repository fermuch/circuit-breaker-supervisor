defmodule CircuitBreakerSupervisor.Monitor do
  @moduledoc """
  Monitors processes held by `CircuitBreakerSupervisor.Supervisor`.
  """

  use GenServer

  alias CircuitBreakerSupervisor.Monitor
  alias CircuitBreakerSupervisor.State

  defstruct backoff: nil,
            children: %{},
            enabled?: nil,
            id_to_ref: %{},
            poll_interval: 0,
            ref_to_id: %{},
            supervisor: nil

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    children =
      Keyword.fetch!(init_arg, :children)
      |> Map.new(fn spec ->
        spec = set_restart_temporary(spec)
        {spec_to_id(spec), %State{spec: spec}}
      end)

    state = %Monitor{
      backoff: Keyword.fetch!(init_arg, :backoff),
      children: children,
      enabled?: Keyword.fetch!(init_arg, :enabled?),
      poll_interval: Keyword.fetch!(init_arg, :poll_interval),
      supervisor: Keyword.fetch!(init_arg, :supervisor)
    }

    # start each child within init to mimic regular Supervisor behavior. rest
    # of supervision tree will not start until each child has had one startup
    # attempt.
    {:ok, check_children(state)}
  end

  @impl true
  def handle_info(:check_children, state), do: {:noreply, check_children(state)}

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %Monitor{ref_to_id: ref_to_id} = state) do
    id = Map.get(ref_to_id, ref)

    # TODO: should normal shutdowns get recorded and prevent the process from
    # being restarted?
    state =
      clear_monitor(state, id)
      |> check_child(id)

    {:noreply, state}
  end

  defp check_children(%Monitor{children: children, poll_interval: poll_interval} = state) do
    # schedule next monitoring loop
    Process.send_after(self(), :check_children, poll_interval)

    # check all children
    Enum.reduce(children, state, fn {id, _}, acc -> check_child(acc, id) end)
  end

  defp check_child(state, id) do
    %State{status: status, spec: spec} = State.get_state(state, id)

    case status do
      :running_disabled -> stop_child(state, id)
      :stopped_past_backoff -> start_child(state, id, spec)
      _ -> state
    end
  end

  defp start_child(%Monitor{supervisor: supervisor} = state, id, spec) do
    state = clear_monitor(state, id)

    case Supervisor.start_child(supervisor, spec) do
      {:ok, pid} ->
        add_monitor(state, id, pid)

      {:ok, pid, _info} ->
        add_monitor(state, id, pid)

      {:error, {:already_started, pid}} ->
        add_monitor(state, id, pid)

      # Any other failure and we don't start the child
      {:error, _reason} ->
        # failure during startup
        state

      :ignore ->
        # failure during startup
        state
    end
  end

  defp stop_child(%Monitor{supervisor: supervisor} = state, id) do
    # monitor will be cleared by handler for :DOWN message 
    Supervisor.terminate_child(supervisor, id)
    state
  end

  defp add_monitor(%Monitor{ref_to_id: ref_to_id, id_to_ref: id_to_ref} = state, id, pid) do
    ref = Process.monitor(pid)
    ref_to_id = Map.put(ref_to_id, ref, id)
    id_to_ref = Map.put(id_to_ref, id, ref)
    %Monitor{state | ref_to_id: ref_to_id, id_to_ref: id_to_ref}
  end

  defp clear_monitor(%Monitor{ref_to_id: ref_to_id, id_to_ref: id_to_ref} = state, id) do
    ref_to_id =
      case Map.get(id_to_ref, id) do
        nil ->
          ref_to_id

        ref ->
          Process.demonitor(ref)
          Map.drop(ref_to_id, [ref])
      end

    id_to_ref = Map.drop(id_to_ref, [id])

    %Monitor{state | id_to_ref: id_to_ref, ref_to_id: ref_to_id}
  end

  defp spec_to_id(%{id: id}), do: id
  defp spec_to_id(%{start: {id, _, _}}), do: id
  defp spec_to_id(id) when is_atom(id), do: id

  defp set_restart_temporary(spec) when is_map(spec), do: Map.put(spec, :restart, :temporary)
  defp set_restart_temporary(spec), do: spec
end
