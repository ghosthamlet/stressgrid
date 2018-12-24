defmodule Stressgrid.Coordinator.GeneratorRegistry do
  @moduledoc false

  use GenServer
  require Logger

  alias Stressgrid.Coordinator.{
    GeneratorRegistry,
    Utils,
    Reporter,
    GeneratorConnection,
    ManagementConnection
  }

  defstruct registrations: %{},
            monitors: %{}

  def register(id) do
    GenServer.cast(__MODULE__, {:register, id, self()})
  end

  def start_cohort(id, blocks, addresses) do
    GenServer.cast(__MODULE__, {:start_cohort, id, blocks, addresses})
  end

  def stop_cohort(id) do
    GenServer.cast(__MODULE__, {:stop_cohort, id})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def get_registration_ids() do
    GenServer.call(__MODULE__, :get_registration_ids)
  end

  def init(_args) do
    {:ok, %GeneratorRegistry{}}
  end

  def handle_call(
        :get_registration_ids,
        _,
        %GeneratorRegistry{registrations: registrations} = registry
      ) do
    {:reply, {:ok, registrations |> Map.keys()}, registry}
  end

  def handle_cast(
        {:register, id, pid},
        %GeneratorRegistry{monitors: monitors, registrations: registrations} = registry
      ) do
    ref = :erlang.monitor(:process, pid)
    Logger.info("Registered generator #{id}")
    :ok = ManagementConnection.notify(%{"generator_changed" => %{"id" => id}})

    {:noreply,
     %{
       registry
       | registrations: registrations |> Map.put(id, pid),
         monitors: monitors |> Map.put(ref, id)
     }}
  end

  def handle_cast(
        {:start_cohort, id, blocks, addresses},
        %GeneratorRegistry{registrations: registrations} = registry
      ) do
    :ok =
      registrations
      |> Enum.zip(Utils.split_blocks(blocks, Map.size(registrations)))
      |> Enum.each(fn {{_, pid}, blocks} ->
        :ok = GeneratorConnection.start_cohort(pid, id, blocks, addresses)
      end)

    {:noreply, registry}
  end

  def handle_cast(
        {:stop_cohort, id},
        %GeneratorRegistry{registrations: registrations} = registry
      ) do
    :ok =
      registrations
      |> Enum.each(fn {_, pid} ->
        :ok = GeneratorConnection.stop_cohort(pid, id)
      end)

    {:noreply, registry}
  end

  def handle_info(
        {:DOWN, ref, :process, _, reason},
        %GeneratorRegistry{
          monitors: monitors,
          registrations: registrations
        } = registry
      ) do
    case monitors |> Map.get(ref) do
      nil ->
        {:noreply, registry}

      id ->
        Logger.info("Unregistered generator #{id}: #{inspect(reason)}")
        :ok = ManagementConnection.notify(%{"generator_removed" => %{"id" => id}})
        :ok = Reporter.clear_stats(id)

        {:noreply,
         %{
           registry
           | registrations: registrations |> Map.delete(id),
             monitors: monitors |> Map.delete(ref)
         }}
    end
  end
end
