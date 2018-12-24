defmodule Stressgrid.Generator.Device do
  @moduledoc false

  alias Stressgrid.Generator.{Device, DeviceContext, Script}

  use GenServer
  require Logger

  @recycle_delay 1_000

  defstruct address: nil,
            task_script: nil,
            task_params: nil,
            task: nil,
            hists: %{},
            counters: %{},
            last_ts: 0,
            conn_pid: nil,
            conn_ref: nil,
            request_from: nil,
            stream_ref: nil,
            response_status: nil,
            response_headers: nil,
            response_iodata: nil

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    _ = Kernel.send(self(), :init)

    {:ok,
     %Device{
       address: args |> Keyword.fetch!(:address),
       task_script: args |> Keyword.fetch!(:script),
       task_params: args |> Keyword.fetch!(:params),
       hists: %{
         conn_us: make_hist(),
         headers_us: make_hist(),
         body_us: make_hist()
       }
     }}
  end

  def request(pid, method, path, headers, body) when is_map(headers) do
    request(pid, method, path, headers |> Map.to_list(), body)
  end

  def request(pid, method, path, headers, body) when is_list(headers) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:request, method, path, headers, body})
    else
      exit(:device_terminated)
    end
  end

  def collect(pid, to_hists) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:collect, to_hists})
    else
      {:ok, false, %{}, %{}}
    end
  end

  def handle_call(
        {:collect, to_hists},
        _,
        %Device{hists: from_hists, counters: counters, task: task} = device
      ) do
    hists = add_hists(to_hists, from_hists)

    :ok =
      from_hists
      |> Enum.each(fn {_, hist} ->
        :ok = :hdr_histogram.reset(hist)
      end)

    reset_counters =
      counters
      |> Enum.map(fn {key, _} -> {key, 0} end)
      |> Map.new()

    {:reply, {:ok, task != nil, hists, counters}, %{device | counters: reset_counters}}
  end

  def handle_call(
        {:request, method, path, headers, body},
        request_from,
        %Device{conn_pid: conn_pid, stream_ref: nil, request_from: nil} = device
      ) do
    Logger.debug("Starting request #{method} #{path}")

    stream_ref = :gun.request(conn_pid, method, path, headers, body)

    device = %{device | stream_ref: stream_ref, request_from: request_from}
    {:noreply, device}
  end

  def handle_info(:init, %Device{conn_pid: nil, address: {:tcp, host, port}} = device) do
    Logger.debug("Open gun")

    ts = :os.system_time(:micro_seconds)

    {:ok, conn_pid} =
      :gun.open(host |> String.to_charlist(), port, %{
        retry: 0,
        http_opts: %{keepalive: :infinity}
      })

    conn_ref = :erlang.monitor(:process, conn_pid)
    {:noreply, %{device | conn_pid: conn_pid, conn_ref: conn_ref, last_ts: ts}}
  end

  def handle_info({task_ref, :ok}, %Device{task: %Task{ref: task_ref}} = device)
      when is_reference(task_ref) do
    Logger.debug("Script exited normally")

    true = :erlang.demonitor(task_ref, [:flush])
    device = %{device | task: nil}

    {:noreply,
     device
     |> recycle()}
  end

  def handle_info(
        {:gun_up, conn_pid, _protocol},
        %Device{
          task_script: task_script,
          task_params: task_params,
          conn_pid: conn_pid,
          last_ts: last_ts
        } = device
      ) do
    Logger.debug("Gun up")

    ts = :os.system_time(:micro_seconds)

    %Macro.Env{functions: functions, macros: macros} = __ENV__

    kernel_functions =
      functions
      |> Enum.find(fn
        {Kernel, _} -> true
        _ -> false
      end)

    kernel_macros =
      macros
      |> Enum.find(fn
        {Kernel, _} -> true
        _ -> false
      end)

    device_pid = self()

    task =
      Task.Supervisor.async_nolink(Script.Supervisor, fn ->
        try do
          task_script
          |> Code.eval_string([device_pid: device_pid, params: task_params],
            functions: [
              kernel_functions,
              {DeviceContext,
               [
                 delay: 1,
                 delay: 2
               ]
               |> Enum.sort()}
            ],
            macros: [
              kernel_macros,
              {DeviceContext,
               [
                 get: 1,
                 get: 2,
                 options: 1,
                 options: 2,
                 delete: 1,
                 delete: 2,
                 post: 1,
                 post: 2,
                 post: 3,
                 put: 1,
                 put: 2,
                 put: 3,
                 patch: 1,
                 patch: 2,
                 patch: 3
               ]
               |> Enum.sort()}
            ]
          )
        catch
          :exit, :device_terminated ->
            :ok
        end

        :ok
      end)

    {:noreply,
     %{device | last_ts: ts, task: task}
     |> record_hist(:conn_us, ts - last_ts)}
  end

  def handle_info(
        {:gun_down, conn_pid, _, reason, _, _},
        %Device{
          conn_pid: conn_pid
        } = device
      ) do
    Logger.debug("Gun down with #{inspect(reason)}")

    {:noreply,
     device
     |> recycle(@recycle_delay)
     |> inc_counter(reason |> reason_to_key(), 1)}
  end

  def handle_info(
        {:gun_response, conn_pid, stream_ref, is_fin, status, headers},
        %Device{
          conn_pid: conn_pid,
          stream_ref: stream_ref,
          last_ts: last_ts
        } = device
      ) do
    ts = :os.system_time(:micro_seconds)

    device =
      %{device | response_status: status, response_headers: headers, response_iodata: []}
      |> record_hist(:headers_us, ts - last_ts)
      |> inc_counter("response_count" |> String.to_atom(), 1)

    case is_fin do
      :nofin ->
        {:noreply, %{device | last_ts: ts}}

      :fin ->
        {:noreply, device |> complete_request()}
    end
  end

  def handle_info(
        {:gun_data, conn_pid, stream_ref, is_fin, data},
        %Device{
          conn_pid: conn_pid,
          stream_ref: stream_ref,
          response_iodata: response_iodata,
          last_ts: last_ts
        } = device
      ) do
    ts = :os.system_time(:micro_seconds)

    device = %{device | response_iodata: [data | response_iodata]}

    case is_fin do
      :nofin ->
        {:noreply, device}

      :fin ->
        {:noreply, device |> record_hist(:body_us, ts - last_ts) |> complete_request()}
    end
  end

  def handle_info(
        {:gun_error, conn_pid, stream_ref, reason},
        %Device{
          stream_ref: stream_ref,
          conn_pid: conn_pid
        } = device
      ) do
    Logger.debug("Gun error #{inspect(reason)}")

    {:noreply,
     device
     |> recycle(@recycle_delay)
     |> inc_counter(reason |> reason_to_key(), 1)}
  end

  def handle_info(
        {:gun_error, conn_pid, reason},
        %Device{
          conn_pid: conn_pid
        } = device
      ) do
    Logger.debug("Gun error #{inspect(reason)}")

    {:noreply,
     device
     |> recycle(@recycle_delay)
     |> inc_counter(reason |> reason_to_key(), 1)}
  end

  def handle_info(
        {:DOWN, conn_ref, :process, conn_pid, reason},
        %Device{
          conn_ref: conn_ref,
          conn_pid: conn_pid
        } = device
      ) do
    Logger.debug("Gun exited with #{inspect(reason)}")

    {:noreply,
     device
     |> recycle(@recycle_delay)
     |> inc_counter(reason |> reason_to_key(), 1)}
  end

  def handle_info(
        {:DOWN, task_ref, :process, task_pid, reason},
        %Device{
          task: %Task{
            ref: task_ref,
            pid: task_pid
          }
        } = device
      ) do
    case reason do
      {%SyntaxError{description: description}, _} ->
        Logger.error("Script syntax error: #{description}")
        {:noreply, device}

      error ->
        Logger.error("Script exited with #{inspect(error)}")

        {:noreply,
         device
         |> recycle(@recycle_delay)
         |> inc_counter(:task_error_count, 1)}
    end
  end

  def handle_info(
        _,
        device
      ) do
    {:noreply, device}
  end

  defp complete_request(
         %Device{
           request_from: request_from,
           response_status: response_status,
           response_headers: response_headers,
           response_iodata: response_iodata
         } = device
       ) do
    Logger.debug("Complete request #{response_status}")

    if request_from != nil do
      response_iodata = response_iodata |> Enum.reverse()

      response_data =
        case response_headers |> List.keyfind("content-type", 0) do
          {_, content_type} ->
            case :cow_http_hd.parse_content_type(content_type) do
              {"application", "json", _} ->
                case Jason.decode(response_iodata) do
                  {:ok, json} ->
                    json

                  _ ->
                    response_iodata
                end

              _ ->
                response_iodata
            end

          _ ->
            response_iodata
        end

      GenServer.reply(
        request_from,
        {response_status, response_headers, response_data}
      )
    end

    %{
      device
      | request_from: nil,
        stream_ref: nil,
        response_status: nil,
        response_headers: nil,
        response_iodata: nil
    }
  end

  defp recycle(%Device{conn_pid: conn_pid, conn_ref: conn_ref, task: task} = device, delay \\ 0) do
    Logger.debug("Recycle device")

    if task != nil do
      Task.shutdown(task, :brutal_kill)
    end

    if conn_ref != nil do
      true = :erlang.demonitor(conn_ref, [:flush])
      _ = :gun.close(conn_pid)
    end

    _ = Process.send_after(self(), :init, delay)

    %{
      device
      | conn_pid: nil,
        conn_ref: nil,
        task: nil,
        request_from: nil,
        stream_ref: nil,
        response_status: nil,
        response_headers: nil,
        response_iodata: nil
    }
  end

  defp add_hists(to_hists, from_hists) do
    from_hists
    |> Enum.reduce(to_hists, fn {key, from_hist}, hists ->
      {hists, to_hist} =
        case hists
             |> Map.get(key) do
          nil ->
            hist = make_hist()
            {hists |> Map.put(key, hist), hist}

          hist ->
            {hists, hist}
        end

      :ok =
        case :hdr_histogram.add(to_hist, from_hist) do
          dropped_count when is_integer(dropped_count) ->
            :ok

          {:error, error} ->
            Logger.error("Error adding hists #{inspect(error)}")
            :ok
        end

      hists
    end)
  end

  defp make_hist do
    {:ok, hist} = :hdr_histogram.open(60_000_000, 3)
    hist
  end

  defp record_hist(%Device{hists: hists} = device, key, value) do
    {device, hist} =
      case hists |> Map.get(key) do
        nil ->
          hist = make_hist()
          {%{device | hists: hists |> Map.put(key, hist)}, hist}

        hist ->
          {device, hist}
      end

    :hdr_histogram.record(hist, value)
    device
  end

  defp inc_counter(%Device{counters: counters} = device, key, value) do
    %{
      device
      | counters:
          counters
          |> Map.update(key, value, fn c -> c + value end)
    }
  end

  defp reason_to_key(error) when is_atom(error) do
    "#{error}_error_count" |> String.to_atom()
  end

  defp reason_to_key({:error, error}) when is_atom(error) do
    "#{error}_error_count" |> String.to_atom()
  end

  defp reason_to_key({:shutdown, error}) when is_atom(error) do
    "#{error}_error_count" |> String.to_atom()
  end

  defp reason_to_key({:stream_error, _, _}) do
    :stream_error_count
  end

  defp reason_to_key({:closed, _}) do
    :closed_error_count
  end

  defp reason_to_key({:badstate, _}) do
    :protocol_error_count
  end

  defp reason_to_key(_) do
    :unknown_error_count
  end
end
