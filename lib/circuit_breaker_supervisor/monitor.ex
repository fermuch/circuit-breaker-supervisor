defmodule CircuitBreakerSupervisor.Monitor do
  @moduledoc """
  Monitors processes held by `CircuitBreakerSupervisor.Supervisor`.
  """

  use GenServer

  alias CircuitBreakerSupervisor.Monitor
  alias CircuitBreakerSupervisor.State

  defstruct children: %{},
            id_to_ref: %{},
            ref_to_id: %{},
            supervisor: nil

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    children =
      Keyword.fetch!(init_arg, :children)
      |> Map.new(&{spec_to_id(&1), %State{spec: &1}})

    state = %Monitor{
      children: children,
      supervisor: Keyword.fetch!(init_arg, :supervisor)
    }

    # start each child within init to mimic regular Supervisor behavior. rest
    # of supervision tree will not start until each child has had one startup
    # attempt.
    {:ok, check_children(state)}
  end

  @impl true
  def handle_info(:check_children, state), do: {:noreply, check_children(state)}

  def check_children(%Monitor{children: children} = state) do
    Enum.reduce(children, state, fn {id, _}, acc -> check_child(acc, id) end)
  end

  defp check_child(%Monitor{children: children} = state, id) do
    running? = State.running?(state, id)

    if running? do
      state
    else
      %State{spec: spec} = Map.fetch!(children, id)
      start_child(state, spec)
    end
  end

  defp start_child(%Monitor{supervisor: supervisor} = state, spec) do
    state = clear_monitor(state, spec)

    case Supervisor.start_child(supervisor, spec) do
      {:ok, pid} ->
        add_monitor(state, spec, pid)

      {:ok, pid, _info} ->
        add_monitor(state, spec, pid)

      {:error, {:already_started, pid}} ->
        add_monitor(state, spec, pid)

      # Any other failure and we don't start the child
      {:error, _reason} ->
        # failure during startup
        state

      :ignore ->
        # failure during startup
        state
    end
  end

  defp add_monitor(%Monitor{ref_to_id: ref_to_id, id_to_ref: id_to_ref} = state, spec, pid) do
    id = spec_to_id(spec)
    ref = Process.monitor(pid)
    ref_to_id = Map.put(ref_to_id, ref, id)
    id_to_ref = Map.put(id_to_ref, id, ref)
    %Monitor{state | ref_to_id: ref_to_id, id_to_ref: id_to_ref}
  end

  defp clear_monitor(%Monitor{ref_to_id: ref_to_id, id_to_ref: id_to_ref} = state, spec) do
    id = spec_to_id(spec)

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
end
