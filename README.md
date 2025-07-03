# Circuit Breaker Supervisor

## Installation

Add `circuit_breaker_supervisor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:circuit_breaker_supervisor, "~> 0.1.0"}
  ]
end
```

Docs can be found at <https://hexdocs.pm/circuit_breaker_supervisor>.

## Usage

This package provides a macro that you can use to implement a custom supervisor:

```elixir
defmodule MyApp.MySupervisor do
  use CircuitBreakerSupervisor, poll_interval: :timer.seconds(1)

  @impl true
  def backoff(attempt) do
    # example exponential backoff with jitter
    trunc(:math.pow(attempt, 4) + 15 + :rand.uniform(30) * attempt)
  end

  @impl true
  def enabled?(id) do
    MyApp.FeatureFlagService.enabled?(id)
  end
end
```

Then start your custom supervisor within your application:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # ...
      {
        CircuitBreakerSupervisor,
        children: [
          # children that should be managed by the circuit breaker, each one
          # must have a unique id
          %{
            id: SomeService.Supervisor,
            start: {SomeService.Supervisor, :start_link, [[]]},
          },
          %{
            id: AnotherService.Supervisor,
            start: {AnotherService.Supervisor, :start_link, [[]]},
          }
        ]
      }
      # start up other children outside of the circuit breaker...
      {MyApp.MySupervisor, arg}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
end
```

## Telemetry

The following events are emitted when child processes are started / stopped:

- `[:circuit_breaker_supervisor, :child, :stop]`
- `[:circuit_breaker_supervisor, :child, :start]`

### Measures

- `attempt_count` - The number of times the process has been restarted since the last time it was considered healthy.

### Metadata

- `id` - The same id that is passed in with the `child_spec`

## Related Projects

- https://knock.app/blog/controlling-elixir-supervisors-at-runtime-with-feature-flags
- https://github.com/mmzeeman/breaky
