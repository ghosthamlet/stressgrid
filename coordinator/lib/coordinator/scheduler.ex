defmodule Stressgrid.Coordinator.Scheduler do
  @moduledoc false

  use GenServer
  require Logger

  alias Stressgrid.Coordinator.{
    Scheduler,
    Utils,
    GeneratorRegistry,
    Reporter,
    ManagementConnection
  }

  @notify_interval 1_000

  defmodule Run do
    defstruct name: nil,
              state: nil,
              remaining_ms: 0,
              timer_refs: [],
              cohort_ids: []
  end

  defstruct runs: %{}

  def run_to_json(id, %Run{name: name, state: state, remaining_ms: remaining_ms}) do
    %{
      "id" => id,
      "name" => name,
      "state" => state |> Atom.to_string(),
      "remaining_ms" => remaining_ms
    }
  end

  def start_run(id, name, blocks, addresses, opts \\ []) do
    GenServer.cast(__MODULE__, {:start_run, id, name, blocks, addresses, opts})
  end

  def abort_run(id) do
    GenServer.cast(__MODULE__, {:abort_run, id})
  end

  def get_runs_json() do
    GenServer.call(__MODULE__, :get_runs_json)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    {:ok, _} = :timer.send_interval(@notify_interval, :notify)
    {:ok, %Scheduler{}}
  end

  def handle_call(:get_runs_json, _, %Scheduler{runs: runs} = scheduler) do
    runs_json =
      runs
      |> Enum.map(fn {id, run} ->
        run_to_json(id, run)
      end)

    {:reply, {:ok, runs_json}, scheduler}
  end

  def handle_info(:notify, %Scheduler{runs: runs} = scheduler) do
    runs =
      runs
      |> Enum.map(fn {id, %Run{remaining_ms: remaining_ms} = run} ->
        remaining_ms = remaining_ms - @notify_interval

        {id, %{run | remaining_ms: remaining_ms}}
      end)
      |> Map.new()

    :ok = notify_runs_changed(runs)

    {:noreply, %{scheduler | runs: runs}}
  end

  def handle_info({:run_op, id, op}, %Scheduler{runs: runs} = scheduler) do
    run = runs |> Map.get(id)

    if run != nil do
      run = run |> run_op(id, op)

      if run != nil do
        {:noreply, %{scheduler | runs: runs |> Map.put(id, run)}}
      else
        {:noreply, %{scheduler | runs: runs |> Map.delete(id)}}
      end
    else
      {:noreply, scheduler}
    end
  end

  def handle_info({:run_status, id, state, remaining_ms}, %Scheduler{runs: runs} = scheduler) do
    run = runs |> Map.get(id)

    if run != nil do
      run = run |> run_status(id, state, remaining_ms)

      {:noreply, %{scheduler | runs: runs |> Map.put(id, run)}}
    else
      {:noreply, scheduler}
    end
  end

  def handle_cast({:abort_run, id}, %Scheduler{runs: runs} = scheduler) do
    run = runs |> Map.get(id)

    if run != nil do
      :ok = abort_run(run, id)

      {:noreply, %{scheduler | runs: runs |> Map.delete(id)}}
    else
      {:noreply, scheduler}
    end
  end

  def handle_cast(
        {:start_run, id, name, blocks, addresses, opts},
        %Scheduler{runs: runs} = scheduler
      ) do
    if not (runs |> Map.has_key?(id)) do
      {:noreply,
       %{scheduler | runs: runs |> Map.put(id, schedule_run(id, name, blocks, addresses, opts))}}
    else
      {:noreply, scheduler}
    end
  end

  defp schedule_run(id, name, blocks, addresses, opts) do
    ramp_steps = opts |> Keyword.get(:ramp_steps, 100)
    rampup_step_ms = opts |> Keyword.get(:rampup_step_ms, 1000)
    sustain_ms = opts |> Keyword.get(:sustain_ms, 300_000)
    rampdown_step_ms = opts |> Keyword.get(:rampdown_step_ms, rampup_step_ms)

    ts = 0
    timer_refs = [schedule_status(ts, id, :rampup, ramp_steps * rampup_step_ms)]
    timer_refs = [schedule_op(ts, id, :start) | timer_refs]

    {ts, timer_refs} =
      1..ramp_steps
      |> Enum.zip(blocks |> Utils.split_blocks(ramp_steps))
      |> Enum.reduce({ts, timer_refs}, fn {i, blocks}, {ts, timer_refs} ->
        {ts + rampup_step_ms,
         [schedule_op(ts, id, {:start_cohort, "#{id}-#{i - 1}", blocks, addresses}) | timer_refs]}
      end)

    timer_refs = [schedule_status(ts, id, :sustain, sustain_ms) | timer_refs]
    ts = ts + sustain_ms
    timer_refs = [schedule_status(ts, id, :rampdown, ramp_steps * rampdown_step_ms) | timer_refs]

    {ts, timer_refs} =
      ramp_steps..1
      |> Enum.reduce({ts, timer_refs}, fn i, {ts, timer_refs} ->
        {ts + rampdown_step_ms,
         [schedule_op(ts, id, {:stop_cohort, "#{id}-#{i - 1}"}) | timer_refs]}
      end)

    timer_refs = [schedule_op(ts, id, :stop) | timer_refs]

    %Run{name: name, timer_refs: timer_refs}
  end

  defp schedule_op(ts, id, op) do
    Logger.info("Run #{id} operation #{inspect(op)} at #{ts}")

    :erlang.send_after(
      ts,
      self(),
      {:run_op, id, op}
    )
  end

  defp schedule_status(ts, id, state, remaining_ms) do
    :erlang.send_after(
      ts,
      self(),
      {:run_status, id, state, remaining_ms}
    )
  end

  defp abort_run(%Run{timer_refs: timer_refs, cohort_ids: cohort_ids}, id) do
    Logger.info("Aborted run #{id}")

    :ok =
      timer_refs
      |> Enum.each(&:erlang.cancel_timer(&1))

    :ok =
      cohort_ids
      |> Enum.each(&GeneratorRegistry.stop_cohort(&1))

    :ok = Reporter.stop_run(id)
    :ok = notify_run_removed(id)

    :ok
  end

  defp notify_run_removed(id) do
    ManagementConnection.notify(%{"run_removed" => %{"id" => id}})
  end

  defp notify_runs_changed(runs) do
    runs
    |> Enum.map(fn {id, run} ->
      %{
        "run_changed" => run_to_json(id, run)
      }
    end)
    |> ManagementConnection.notify_many()
  end

  defp run_op(%Run{name: name} = run, id, :start) do
    Logger.info("Started run #{id}")
    :ok = Reporter.start_run(id, name)
    :ok = ManagementConnection.notify(%{"run_changed" => %{"id" => id, "name" => name}})
    run
  end

  defp run_op(_, id, :stop) do
    Logger.info("Stopped run #{id}")
    :ok = Reporter.stop_run(id)
    :ok = notify_run_removed(id)
    nil
  end

  defp run_op(
         %Run{cohort_ids: cohort_ids} = run,
         _,
         {:start_cohort, cohort_id, blocks, addresses}
       ) do
    Logger.info("Started cohort #{cohort_id}")
    :ok = GeneratorRegistry.start_cohort(cohort_id, blocks, addresses)
    %{run | cohort_ids: [cohort_id | cohort_ids]}
  end

  defp run_op(%Run{cohort_ids: cohort_ids} = run, _, {:stop_cohort, cohort_id}) do
    Logger.info("Stopped cohort #{cohort_id}")
    :ok = GeneratorRegistry.stop_cohort(cohort_id)
    %{run | cohort_ids: cohort_ids |> List.delete(cohort_id)}
  end

  defp run_status(run, id, state, remaining_ms) do
    run = %{run | state: state, remaining_ms: remaining_ms}
    :ok = notify_runs_changed([{id, run}])
    run
  end
end
