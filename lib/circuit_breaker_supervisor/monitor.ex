defmodule CircuitBreakerSupervisor.Monitor do
  @moduledoc """
  Monitors processes held by `CircuitBreakerSupervisor.Supervisor`.
  """

  use GenServer

  alias CircuitBreakerSupervisor.State

  defstruct children: [],
            id_to_ref: %{},
            ref_to_id: %{},
            supervisor: nil

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    state = %__MODULE__{
      children: Keyword.fetch!(init_arg, :children),
      supervisor: Keyword.fetch!(init_arg, :supervisor)
    }

    # start each child within init to mimic regular Supervisor behavior. rest
    # of supervision tree will not start until each child has had one startup
    # attempt.
    {:ok, check_children(state)}
  end

  @impl true
  def handle_info(:check_children, state), do: {:noreply, check_children(state)}

  def check_children(%__MODULE__{children: children} = state) do
    Enum.reduce(children, state, &check_child(&2, &1))
  end

  defp check_child(state, spec) do
    id = spec_to_id(spec)
    running? = State.running?(state, id)

    if running? do
      state
    else
      start_child(state, spec)
    end
  end

  defp start_child(%__MODULE__{supervisor: supervisor} = state, spec) do
    state = clear_monitor(state, spec)

    case Supervisor.start_child(supervisor, spec) do
      {:ok, pid} ->
        monitor_pid(state, spec, pid)

      {:ok, pid, _info} ->
        monitor_pid(state, spec, pid)

      {:error, {:already_started, pid}} ->
        monitor_pid(state, spec, pid)

      # Any other failure and we don't start the child
      {:error, _reason} ->
        # failure during startup
        state

      :ignore ->
        # failure during startup
        state
    end
  end

  defp monitor_pid(%__MODULE__{ref_to_id: ref_to_id, id_to_ref: id_to_ref} = state, spec, pid) do
    id = spec_to_id(spec)
    ref = Process.monitor(pid)
    ref_to_id = Map.put(ref_to_id, ref, id)
    id_to_ref = Map.put(id_to_ref, id, ref)

    %__MODULE__{state | ref_to_id: ref_to_id, id_to_ref: id_to_ref}
  end

  defp clear_monitor(%__MODULE__{ref_to_id: ref_to_id, id_to_ref: id_to_ref} = state, spec) do
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

    %__MODULE__{state | id_to_ref: id_to_ref, ref_to_id: ref_to_id}
  end

  defp spec_to_id(%{start: {id, _, _}}), do: id
  defp spec_to_id(%{id: id}), do: id
  defp spec_to_id(id) when is_atom(id), do: id
end
