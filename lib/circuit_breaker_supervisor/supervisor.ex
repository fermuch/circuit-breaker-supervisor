defmodule CircuitBreakerSupervisor.Supervisor do
  @moduledoc """
  A regular supervisor that is started up to hold all the children supervised
  by the `CircuitBreakerSupervisor`.

  `Supervisor` is used rather than `DynamicSupervisor` because `Supervisor`
  tracks the ids that are assigned to children. `DynamicSupervisor` only returns
  `:undefined` ids when `which_children` is called, making it difficult to use.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, [], opts)
  end

  @impl true
  def init(_init_arg) do
    # start with no children
    Supervisor.init([], strategy: :one_for_one)
  end
end
