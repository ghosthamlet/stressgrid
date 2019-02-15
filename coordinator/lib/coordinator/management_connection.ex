defmodule Stressgrid.Coordinator.ManagementConnection do
  @moduledoc false

  alias Stressgrid.Coordinator.{ManagementConnection, Scheduler, GeneratorRegistry, Reporter}

  @behaviour :cowboy_websocket

  require Logger

  defstruct []

  def init(req, _) do
    {:cowboy_websocket, req, %ManagementConnection{}, %{idle_timeout: :infinity}}
  end

  def websocket_init(%{} = connection) do
    {:ok, registration_ids} = GeneratorRegistry.get_registration_ids()
    {:ok, runs} = Scheduler.get_runs_json()
    {:ok, reports} = Reporter.get_reports_json()
    {:ok, utilizations, active_counts} = Reporter.get_conns_info()

    generators =
      registration_ids
      |> Enum.map(fn id ->
        active_count =
          active_counts
          |> Map.get(id)

        utilization =
          utilizations
          |> Map.get(id)

        %{
          "id" => id,
          "active_count" => active_count
        }
        |> Map.merge(Reporter.utilization_to_json(utilization))
      end)

    :ok =
      send_json(self(), [
        %{
          "init" => %{
            "runs" => runs,
            "generators" => generators,
            "reports" => reports
          }
        }
      ])

    Registry.register(ManagementConnection, nil, nil)
    {:ok, connection}
  end

  def websocket_handle({:text, text}, connection) do
    connection =
      Jason.decode!(text)
      |> Enum.reduce(connection, &receive_json(&2, &1))

    {:ok, connection}
  end

  def websocket_handle({:ping, data}, connection) do
    {:reply, {:pong, data}, connection}
  end

  def websocket_info({:send, json}, connection) do
    text = Jason.encode!(json)
    {:reply, {:text, text}, connection}
  end

  def notify(json) do
    Registry.lookup(ManagementConnection, nil)
    |> Enum.each(fn {pid, nil} ->
      send_json(pid, [%{"notify" => json}])
    end)
  end

  def notify_many([]) do
    :ok
  end

  def notify_many(jsons) do
    Registry.lookup(ManagementConnection, nil)
    |> Enum.each(fn {pid, nil} ->
      send_json(pid, jsons |> Enum.map(fn json -> %{"notify" => json} end))
    end)
  end

  defp send_json(pid, json) do
    _ = Kernel.send(pid, {:send, json})
    :ok
  end

  defp receive_json(
         %ManagementConnection{} = connection,
         %{
           "run_plan" =>
             %{
               "name" => name,
               "blocks" => blocks_json,
               "addresses" => addresses_json,
               "opts" => opts_json
             } = plan
         }
       )
       when is_binary(name) and is_list(blocks_json) and is_list(addresses_json) do
    safe_name =
      name
      |> String.replace(~r/[^a-zA-Z0-9]+/, "-")
      |> String.trim("-")

    now =
      DateTime.utc_now()
      |> DateTime.to_iso8601(:basic)
      |> String.replace(~r/[TZ\.]/, "")

    id = "#{safe_name}-#{now}"
    script = plan |> Map.get("script")
    opts = parse_opts_json(opts_json)

    blocks =
      blocks_json
      |> Enum.reduce([], fn block_json, acc ->
        case parse_block_json(block_json) do
          %{script: _} = block ->
            [block | acc]

          block ->
            if is_binary(script) do
              [block |> Map.put(:script, script) | acc]
            else
              acc
            end
        end
      end)
      |> Enum.reverse()

    addresses =
      addresses_json
      |> Enum.reduce([], fn address_json, acc ->
        case parse_address_json(address_json) do
          {_, host, _} = address when is_binary(host) ->
            [address | acc]

          _ ->
            acc
        end
      end)
      |> Enum.reverse()

    :ok = Scheduler.start_run(id, name, blocks, addresses, opts)
    connection
  end

  defp receive_json(
         %ManagementConnection{} = connection,
         %{
           "abort_run" => %{
             "id" => id
           }
         }
       )
       when is_binary(id) do
    :ok = Scheduler.abort_run(id)
    connection
  end

  defp receive_json(
         %ManagementConnection{} = connection,
         %{
           "remove_report" => %{
             "id" => id
           }
         }
       )
       when is_binary(id) do
    :ok = Reporter.remove_report(id)
    connection
  end

  defp parse_opts_json(json) do
    json
    |> Enum.reduce([], fn
      {"ramp_steps", ramp_steps}, acc when is_integer(ramp_steps) ->
        [{:ramp_steps, ramp_steps} | acc]

      {"rampup_step_ms", ms}, acc when is_integer(ms) ->
        [{:rampup_step_ms, ms} | acc]

      {"sustain_ms", ms}, acc when is_integer(ms) ->
        [{:sustain_ms, ms} | acc]

      {"rampdown_step_ms", ms}, acc when is_integer(ms) ->
        [{:rampdown_step_ms, ms} | acc]

      _, acc ->
        acc
    end)
  end

  defp parse_block_json(json) do
    json
    |> Enum.reduce([], fn
      {"script", script}, acc when is_binary(script) ->
        [{:script, script} | acc]

      {"params", params}, acc when is_map(params) ->
        [{:params, params} | acc]

      {"size", size}, acc when is_integer(size) ->
        [{:size, size} | acc]

      _, acc ->
        acc
    end)
    |> Map.new()
  end

  defp parse_address_json(json) do
    json
    |> Enum.reduce({:tcp, nil, 80}, fn
      {"host", host}, acc when is_binary(host) ->
        acc |> put_elem(1, host)

      {"port", port}, acc when is_integer(port) ->
        acc |> put_elem(2, port)

      {"protocol", "http"}, acc ->
        acc |> put_elem(0, :tcp)

      {"protocol", "https"}, acc ->
        acc |> put_elem(0, :tls)

      _, acc ->
        acc
    end)
  end
end
