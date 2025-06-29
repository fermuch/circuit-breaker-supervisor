defmodule CircuitBreakerSupervisor do
  @moduledoc """
  Documentation for `CircuitBreakerSupervisor`.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    children = Keyword.get(init_arg, :children, [])

    [
      {DynamicSupervisor, name: __MODULE__.Supervisor, strategy: :one_for_one},
      {__MODULE__.Monitor, children: children, supervisor: __MODULE__.Supervisor}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
