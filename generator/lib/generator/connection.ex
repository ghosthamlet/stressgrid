defmodule Stressgrid.Generator.Connection do
  @moduledoc false

  use GenServer
  require Logger

  alias Stressgrid.Generator.{Connection, Cohort, Device}

  @conn_timeout 5_000
  @report_interval 1_000

  defstruct id: nil,
            conn_pid: nil,
            cpu_busy: nil,
            cpu_idle: nil,
            net_bytes_rx: nil,
            net_bytes_tx: nil,
            timeout_ref: nil,
            stream_ref: nil,
            hists: %{},
            counters: %{},
            cohorts: %{}

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    host = args |> Keyword.fetch!(:host)
    port = args |> Keyword.fetch!(:port)

    {:ok, conn_pid} =
      :gun.open(
        host |> String.to_charlist(),
        port,
        %{
          retry: 0
        }
      )

    {:ok, timeout_ref} = :timer.send_after(@conn_timeout, :timeout)

    Logger.info("Connecting to coordinator at #{host}:#{port}...")

    {:ok,
     %Connection{id: args |> Keyword.fetch!(:id), conn_pid: conn_pid, timeout_ref: timeout_ref}}
  end

  def handle_info(
        :timeout,
        %Connection{conn_pid: conn_pid} = connection
      ) do
    Logger.warn("Connection timeout")

    :ok = :gun.close(conn_pid)

    {:stop, :shutdown, connection}
  end

  def handle_info(
        {:gun_up, conn_pid, _protocol},
        %Connection{conn_pid: conn_pid} = connection
      ) do
    stream_ref = :gun.ws_upgrade(conn_pid, "/")
    {:noreply, %{connection | stream_ref: stream_ref}}
  end

  def handle_info(
        {:gun_down, conn_pid, :ws, reason, _, _},
        %Connection{conn_pid: conn_pid, cohorts: cohorts} = connection
      ) do
    :ok =
      cohorts
      |> Enum.each(fn {_, pid} ->
        :ok = Cohort.Supervisor.terminate_child(pid)
      end)

    {:stop, {:disconnected, reason}, connection}
  end

  def handle_info(
        {:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers},
        %Connection{id: id, conn_pid: conn_pid, stream_ref: stream_ref, timeout_ref: timeout_ref} =
          connection
      ) do
    connection =
      connection
      |> register(id)

    Logger.info("Connected")

    {:ok, :cancel} = :timer.cancel(timeout_ref)
    {:ok, _} = :timer.send_interval(@report_interval, :report)

    {:noreply, %{connection | timeout_ref: nil}}
  end

  def handle_info(
        {:gun_response, conn_pid, _, _, status, _headers},
        %Connection{conn_pid: conn_pid} = connection
      ) do
    Logger.error("Connection error upgrading to ws: #{status}")
    {:stop, :shutdown, connection}
  end

  def handle_info(
        {:gun_error, conn_pid, stream_ref, reason},
        %Connection{conn_pid: conn_pid, stream_ref: stream_ref} = connection
      ) do
    Logger.error("Connection error: #{inspect(reason)}")
    {:stop, :shutdown, connection}
  end

  def handle_info(
        {:gun_ws, conn_pid, stream_ref, {:binary, frame}},
        %Connection{conn_pid: conn_pid, stream_ref: stream_ref} = connection
      ) do
    connection =
      :erlang.binary_to_term(frame)
      |> Enum.reduce(connection, &receive_term(&2, &1))

    {:noreply, connection}
  end

  def handle_info(
        {:gun_ws, conn_pid, stream_ref, _},
        %Connection{conn_pid: conn_pid, stream_ref: stream_ref} = connection
      ) do
    {:noreply, connection}
  end

  def handle_info(:report, %Connection{} = connection) do
    {hists, counters, active_count} =
      Supervisor.which_children(Cohort.Supervisor)
      |> Enum.reduce({%{}, %{}, 0}, fn {_, cohort_pid, _, _}, a ->
        Supervisor.which_children(cohort_pid)
        |> Enum.reduce(a, fn {_, device_pid, _, _}, {hists, counters, active_count} ->
          {:ok, is_active, hists, device_counters} = Device.collect(device_pid, hists)

          counters =
            device_counters
            |> Enum.reduce(counters, fn {key, value}, counters ->
              counters
              |> Map.update(key, value, fn c -> c + value end)
            end)

          {hists, counters, active_count + if(is_active, do: 1, else: 0)}
        end)
      end)

    {:ok, cpu, connection} =
      connection
      |> cpu_utilization()

    {:ok, network_rx, network_tx, connection} =
      connection
      |> network_utilization()

    utilization = %{cpu: cpu, network_rx: network_rx, network_tx: network_tx}

    connection =
      connection
      |> push_stats(utilization, active_count, counters, hists)

    {:noreply, connection}
  end

  defp receive_term(
         %Connection{cohorts: cohorts} = connection,
         {:start_cohort, %{id: id, blocks: blocks, addresses: addresses}}
       )
       when is_binary(id) and is_list(blocks) do
    {:ok, cohort_pid} = Cohort.Supervisor.start_child(id)

    [address] = addresses

    :ok =
      blocks
      |> Enum.each(fn %{script: script} = block when is_binary(script) ->
        params = block |> Map.get(:params, %{})
        size = block |> Map.get(:size, 1)

        :ok =
          1..size
          |> Enum.each(fn i ->
            {:ok, _} =
              Device.Supervisor.start_child(
                cohort_pid,
                "#{id}-#{i}",
                address,
                script,
                params
              )
          end)
      end)

    %{connection | cohorts: cohorts |> Map.put(id, cohort_pid)}
  end

  defp receive_term(
         %Connection{cohorts: cohorts} = connection,
         {:stop_cohort, %{id: id}}
       )
       when is_binary(id) do
    case cohorts |> Map.get(id) do
      nil ->
        connection

      pid ->
        :ok = Cohort.Supervisor.terminate_child(pid)
        %{connection | cohorts: cohorts |> Map.delete(id)}
    end
  end

  defp send_terms(%Connection{conn_pid: conn_pid} = connection, terms) when is_list(terms) do
    :ok = :gun.ws_send(conn_pid, {:binary, :erlang.term_to_binary(terms)})
    connection
  end

  defp register(connection, id) do
    connection
    |> send_terms([{:register, %{id: id}}])
  end

  defp push_stats(connection, utilization, active_count, counters, hists) do
    hist_binaries =
      hists
      |> Enum.map(fn {key, hist} ->
        {key, :hdr_histogram.to_binary(hist)}
      end)
      |> Map.new()

    connection
    |> send_terms([
      {:push_stats,
       %{
         utilization: utilization,
         active_count: active_count,
         counters: counters,
         hist_binaries: hist_binaries
       }}
    ])
  end

  def read_net_dev do
    case File.read("/proc/net/dev") do
      {:ok, r} ->
        case r |> String.split("\n", trim: true) do
          [_ | [_ | devs]] ->
            devs
            |> Enum.reduce(:error, fn
              dev, :error ->
                case dev |> String.split(" ", trim: true) do
                  [header | info] when header !== "lo:" ->
                    bytes_rx = info |> Enum.at(0) |> String.to_integer()
                    bytes_tx = info |> Enum.at(8) |> String.to_integer()

                    {:ok, bytes_rx, bytes_tx}

                  _ ->
                    :error
                end

              _, r ->
                r
            end)

          _ ->
            :error
        end

      error ->
        error
    end
  end

  defp read_stat do
    case File.read("/proc/stat") do
      {:ok, r} ->
        case r |> String.split("\n", trim: true) do
          [line0 | _] ->
            case line0 |> String.split(" ", trim: true) do
              ["cpu" | [user | [nice | [system | [idle | _]]]]] ->
                busy =
                  String.to_integer(user) + String.to_integer(nice) + String.to_integer(system)

                {:ok, busy, String.to_integer(idle)}

              _ ->
                :error
            end

          _ ->
            :error
        end

      error ->
        error
    end
  end

  defp cpu_utilization(%Connection{cpu_busy: nil, cpu_idle: nil} = connection) do
    case read_stat() do
      {:ok, busy, idle} ->
        {:ok, 0, %{connection | cpu_busy: busy, cpu_idle: idle}}

      _ ->
        {:ok, 0, connection}
    end
  end

  defp cpu_utilization(%Connection{cpu_busy: busy0, cpu_idle: idle0} = connection) do
    case read_stat() do
      {:ok, busy1, idle1} ->
        {:ok, (busy1 - busy0) / (busy1 + idle1 - (busy0 + idle0)),
         %{connection | cpu_busy: busy1, cpu_idle: idle1}}

      _ ->
        {:ok, 0, %{connection | cpu_busy: nil, cpu_idle: nil}}
    end
  end

  defp network_utilization(%Connection{net_bytes_rx: nil, net_bytes_tx: nil} = connection) do
    case read_net_dev() do
      {:ok, bytes_rx, bytes_tx} ->
        {:ok, 0, 0, %{connection | net_bytes_rx: bytes_rx, net_bytes_tx: bytes_tx}}

      _ ->
        {:ok, 0, 0, connection}
    end
  end

  defp network_utilization(
         %Connection{net_bytes_rx: bytes_rx0, net_bytes_tx: bytes_tx0} = connection
       ) do
    case read_net_dev() do
      {:ok, bytes_rx1, bytes_tx1} ->
        {:ok, bytes_rx1 - bytes_rx0, bytes_tx1 - bytes_tx0,
         %{connection | net_bytes_rx: bytes_rx1, net_bytes_tx: bytes_tx1}}

      _ ->
        {:ok, 0, %{connection | net_bytes_rx: nil, net_bytes_tx: nil}}
    end
  end
end
