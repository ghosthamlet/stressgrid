defmodule Stressgrid.Generator.Cohort.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Stressgrid.Generator.{Device}

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(_id) do
    DynamicSupervisor.start_child(
      __MODULE__,
      Device.Supervisor
    )
  end

  def terminate_child(pid) do
    DynamicSupervisor.terminate_child(
      __MODULE__,
      pid
    )
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
