defmodule Stressgrid.Coordinator.Reporter do
  use GenServer

  alias Stressgrid.Coordinator.{Reporter, ManagementConnection}

  defstruct writer_configs: [],
            conn_utilizations: %{},
            conn_active_counts: %{},
            runs: %{},
            reports: %{}

  @report_interval 60_000
  @notify_interval 1_000

  defmodule Run do
    defstruct name: nil,
              clock: 0,
              hists: %{},
              counters: %{},
              prev_counters: %{},
              max_utilization: nil,
              writers: []
  end

  defmodule Report do
    defstruct name: nil,
              max_utilization: nil,
              result_json: %{}
  end

  def utilization_to_json(utilization, prefix \\ "")

  def utilization_to_json(nil, _) do
    %{}
  end

  def utilization_to_json(%{cpu: cpu, network_rx: network_rx, network_tx: network_tx}, prefix) do
    %{
      "#{prefix}cpu" => cpu,
      "#{prefix}network_rx" => network_rx,
      "#{prefix}network_tx" => network_tx
    }
  end

  def report_to_json(id, %Report{
        name: name,
        result_json: result_json,
        max_utilization: max_utilization
      }) do
    %{
      "id" => id,
      "name" => name,
      "result" => result_json
    }
    |> Map.merge(utilization_to_json(max_utilization, "max_"))
  end

  def get_conns_info() do
    GenServer.call(__MODULE__, :get_conns_info)
  end

  def push_stats(conn_id, utilization, active_count, counters, hist_binaries) do
    GenServer.cast(
      __MODULE__,
      {:push_stats, conn_id, utilization, active_count, counters, hist_binaries}
    )
  end

  def start_run(id, name) do
    GenServer.cast(__MODULE__, {:start_run, id, name})
  end

  def stop_run(id) do
    GenServer.cast(__MODULE__, {:stop_run, id})
  end

  def remove_report(id) do
    GenServer.cast(__MODULE__, {:remove_report, id})
  end

  def clear_stats(conn_id) do
    GenServer.cast(__MODULE__, {:clear_stats, conn_id})
  end

  def get_reports_json() do
    GenServer.call(__MODULE__, :get_reports_json)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    Process.send_after(self(), :notify, @notify_interval)

    {:ok, %Reporter{writer_configs: args |> Keyword.get(:writer_configs, [])}}
  end

  def handle_call(
        :get_conns_info,
        _,
        %Reporter{
          conn_utilizations: conn_utilizations,
          conn_active_counts: conn_active_counts
        } = reporter
      ) do
    {:reply, {:ok, conn_utilizations, conn_active_counts}, reporter}
  end

  def handle_call(:get_reports_json, _, %Reporter{reports: reports} = reporter) do
    reports_json =
      reports
      |> Enum.map(fn {id, report} ->
        report_to_json(id, report)
      end)

    {:reply, {:ok, reports_json}, reporter}
  end

  def handle_cast(
        {:push_stats, conn_id, utilization, active_count, push_counters, push_hist_binaries},
        %Reporter{
          conn_active_counts: conn_active_counts,
          conn_utilizations: conn_utilizations,
          runs: runs
        } = reporter
      ) do
    conn_active_counts =
      conn_active_counts
      |> Map.put(conn_id, active_count)

    conn_utilizations =
      conn_utilizations
      |> Map.put(conn_id, utilization)

    max_utilization =
      conn_utilizations
      |> Map.values()
      |> Enum.reduce(nil, &max_utilization(&1, &2))

    runs =
      runs
      |> Enum.map(fn {id,
                      %Run{counters: counters, hists: hists, max_utilization: max_utilization0} =
                        run} ->
        counters =
          push_counters
          |> Enum.reduce(counters, fn {key, value}, counters ->
            counters
            |> Map.update(key, value, fn c -> c + value end)
          end)

        hists =
          push_hist_binaries
          |> Enum.reduce(hists, fn {key, push_hist_binary}, hists ->
            {:ok, push_hist} = :hdr_histogram.from_binary(push_hist_binary)

            hists
            |> Map.update(key, push_hist, fn hist ->
              :hdr_histogram.add(hist, push_hist)
              :hdr_histogram.close(push_hist)
              hist
            end)
          end)

        {id,
         %{
           run
           | hists: hists,
             counters: counters,
             max_utilization: max_utilization(max_utilization, max_utilization0)
         }}
      end)
      |> Map.new()

    {:noreply,
     %{
       reporter
       | conn_active_counts: conn_active_counts,
         conn_utilizations: conn_utilizations,
         runs: runs
     }}
  end

  def handle_cast(
        {:start_run, id, name},
        %Reporter{runs: runs, writer_configs: writer_configs} = reporter
      ) do
    writers =
      writer_configs
      |> Enum.map(fn {module, params} ->
        Kernel.apply(module, :init, params)
      end)

    send(self(), {:report, id})

    {:noreply, %{reporter | runs: runs |> Map.put(id, %Run{name: name, writers: writers})}}
  end

  def handle_cast(
        {:stop_run, id},
        %Reporter{runs: runs, reports: reports, writer_configs: writer_configs} = reporter
      ) do
    case runs |> Map.get(id) do
      %Run{name: name, max_utilization: max_utilization, writers: writers} ->
        result_json =
          Enum.zip(writer_configs, writers)
          |> Enum.reduce(%{}, fn {{module, _}, writer}, r ->
            Kernel.apply(module, :finish, [r, id, writer])
          end)

        report = %Report{name: name, max_utilization: max_utilization, result_json: result_json}

        :ok = ManagementConnection.notify(%{"report_added" => report_to_json(id, report)})

        {:noreply,
         %{
           reporter
           | runs: runs |> Map.delete(id),
             reports: reports |> Map.put(id, report)
         }}

      nil ->
        {:noreply, reporter}
    end
  end

  def handle_cast(
        {:clear_stats, conn_id},
        %Reporter{
          conn_active_counts: conn_active_counts,
          conn_utilizations: conn_utilizations
        } = reporter
      ) do
    conn_active_counts =
      conn_active_counts
      |> Map.delete(conn_id)

    conn_utilizations =
      conn_utilizations
      |> Map.delete(conn_id)

    {:noreply,
     %{
       reporter
       | conn_active_counts: conn_active_counts,
         conn_utilizations: conn_utilizations
     }}
  end

  def handle_cast(
        {:remove_report, id},
        %Reporter{reports: reports} = reporter
      ) do
    case reports |> Map.get(id) do
      %Report{} ->
        :ok = ManagementConnection.notify(%{"report_removed" => %{"id" => id}})

        {:noreply,
         %{
           reporter
           | reports: reports |> Map.delete(id)
         }}

      nil ->
        {:noreply, reporter}
    end
  end

  def handle_info(
        {:report, id},
        %Reporter{
          writer_configs: writer_configs,
          conn_utilizations: conn_utilizations,
          conn_active_counts: conn_active_counts,
          runs: runs
        } = reporter
      ) do
    case runs |> Map.get(id) do
      %Run{
        clock: clock,
        counters: counters,
        prev_counters: prev_counters,
        hists: hists,
        writers: writers
      } = run ->
        Process.send_after(self(), {:report, id}, @report_interval)

        rates =
          prev_counters
          |> Enum.map(fn {key, prev_value} ->
            value =
              counters
              |> Map.get(key)

            {"#{key}_per_second" |> String.to_atom(),
             (value - prev_value) / (@report_interval / 1_000)}
          end)
          |> Map.new()

        scalars =
          counters
          |> Map.merge(rates)

        writers =
          Enum.zip(writer_configs, writers)
          |> Enum.map(fn {{module, _}, writer} ->
            writer = Kernel.apply(module, :write_hists, [id, clock, writer, hists])
            writer = Kernel.apply(module, :write_scalars, [id, clock, writer, scalars])

            writer =
              Kernel.apply(module, :write_utilizations, [
                id,
                clock,
                writer,
                conn_utilizations |> Map.to_list()
              ])

            Kernel.apply(module, :write_active_counts, [
              id,
              clock,
              writer,
              conn_active_counts |> Map.to_list()
            ])
          end)

        hists
        |> Enum.each(fn {_, hist} ->
          :ok = :hdr_histogram.reset(hist)
        end)

        run = %{run | clock: clock + 1, prev_counters: counters, hists: hists, writers: writers}

        {:noreply, %{reporter | runs: runs |> Map.put(id, run)}}

      nil ->
        {:noreply, %{reporter | runs: runs}}
    end
  end

  def handle_info(
        :notify,
        %Reporter{
          conn_utilizations: conn_utilizations,
          conn_active_counts: conn_active_counts
        } = reporter
      ) do
    Process.send_after(self(), :notify, @notify_interval)

    :ok =
      conn_utilizations
      |> Enum.map(fn {id, %{cpu: cpu, network_rx: network_rx, network_tx: network_tx}} ->
        conn_active_count =
          conn_active_counts
          |> Map.get(id)

        %{
          "generator_changed" => %{
            "id" => id,
            "cpu" => cpu,
            "network_rx" => network_rx,
            "network_tx" => network_tx,
            "active_count" => conn_active_count
          }
        }
      end)
      |> ManagementConnection.notify_many()

    {:noreply, reporter}
  end

  defp max_utilization(nil, _) do
    nil
  end

  defp max_utilization(utilization, nil) do
    utilization
  end

  defp max_utilization(%{cpu: cpu0, network_rx: network_rx0, network_tx: network_tx0}, %{
         cpu: cpu1,
         network_rx: network_rx1,
         network_tx: network_tx1
       }) do
    %{
      cpu: max(cpu0, cpu1),
      network_rx: max(network_rx0, network_rx1),
      network_tx: max(network_tx0, network_tx1)
    }
  end
end
