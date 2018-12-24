defmodule Stressgrid.Generator.Device.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Stressgrid.Generator.{Device}

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  def start_child(cohort_pid, id, address, script, params) do
    DynamicSupervisor.start_child(
      cohort_pid,
      {Device, id: id, address: address, script: script, params: params}
    )
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
