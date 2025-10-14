defmodule CircuitBreakerSupervisor do
  @moduledoc """
  A behaviour module and macro for implementing supervisors with a circuit
  breaker for crashed children.
  """

  @doc """
  Given the number of attempts (how many times the process has crashed),
  determine how long to wait before restarting, in milliseconds. Returning
  `:timer.seconds(n)` also works.

  If this callback is not implemented, all crashed processes will be restarted
  without a delay.
  """
  @callback backoff(attempt :: pos_integer()) :: pos_integer()

  @doc """
  Given the id of a supervised process, determine if it should be running.

  If this callback is not implemented, all supervised processes will be
  enabled.

  This callback should be used to connect monitored processes to feature flags.
  """
  @callback enabled?(id :: atom()) :: boolean()

  @optional_callbacks backoff: 1, enabled?: 1

  defmacro __using__(opts) do
    quote do
      use Supervisor

      @behaviour CircuitBreakerSupervisor

      def start_link(init_arg) do
        if Keyword.has_key?(init_arg, :name) do
          Supervisor.start_link(__MODULE__, init_arg, name: Keyword.get(init_arg, :name))
        else
          id = UUID.uuid4()
          init_arg = Keyword.put(init_arg, :id, id)

          Supervisor.start_link(__MODULE__, init_arg,
            name: {:global, {:circuit_breaker_supervisor, id}}
          )
        end
      end

      @impl true
      def init(init_arg) do
        children = Keyword.get(init_arg, :children, [])
        id = Keyword.get(init_arg, :id, UUID.uuid4())

        backoff_fn = if Kernel.function_exported?(__MODULE__, :backoff, 1), do: &backoff/1
        enabled_fn = if Kernel.function_exported?(__MODULE__, :enabled?, 1), do: &enabled?/1

        sub_sup_default = {:global, {:circuit_breaker_sub_supervisor, id}}
        mtr_sup_default = {:global, {:circuit_breaker_monitor, id}}
        sub_sup_name = Keyword.get(init_arg, :sub_name, sub_sup_default)
        mtr_sup_name = Keyword.get(init_arg, :mtr_name, mtr_sup_default)

        [
          {CircuitBreakerSupervisor.Supervisor, name: sub_sup_name},
          {CircuitBreakerSupervisor.Monitor,
           name: mtr_sup_name,
           backoff: backoff_fn,
           child_startup_time: unquote(Keyword.get(opts, :child_startup_time, 60_000)),
           children: children,
           enabled?: enabled_fn,
           poll_interval: unquote(Keyword.get(opts, :poll_interval, 1000)),
           supervisor: sub_sup_name}
        ]
        |> Supervisor.init(strategy: :one_for_one)
      end
    end
  end
end
