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

  defmacro __using__(_opts) do
    quote do
      use Supervisor

      @behaviour CircuitBreakerSupervisor

      def start_link(init_arg) do
        Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      @impl true
      def init(init_arg) do
        children = Keyword.get(init_arg, :children, [])

        backoff_fn = if Kernel.function_exported?(__MODULE__, :backoff, 1), do: &backoff/1
        enabled_fn = if Kernel.function_exported?(__MODULE__, :enabled?, 1), do: &enabled?/1

        [
          {CircuitBreakerSupervisor.Supervisor, name: __MODULE__.Supervisor},
          {CircuitBreakerSupervisor.Monitor,
           backoff: backoff_fn,
           children: children,
           enabled?: enabled_fn,
           supervisor: __MODULE__.Supervisor}
        ]
        |> Supervisor.init(strategy: :one_for_one)
      end
    end
  end
end
