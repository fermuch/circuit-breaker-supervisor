defmodule DummyFeatureFlagService do
  @moduledoc """
  Dummy feature flag service for use in tests. Stores list of disabled ids.
  """

  use Agent

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def enabled?(id) do
    Agent.get(__MODULE__, &(id not in &1))
  end

  def enable(id) do
    Agent.update(__MODULE__, &Enum.reject(&1, fn x -> x == id end))
  end

  def disable(id) do
    Agent.update(__MODULE__, &[id | &1])
  end
end
