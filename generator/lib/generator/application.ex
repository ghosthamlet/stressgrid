defmodule Stressgrid.Generator.Application do
  @moduledoc false

  alias Stressgrid.Generator.{Connection, Cohort, Script}

  use Application

  @default_coordinator_url "ws://localhost:9696"

  def start(_type, _args) do
    id =
      System.get_env()
      |> Map.get("GENERATOR_ID", default_generator_id())

    {host, port} =
      case System.get_env()
           |> Map.get("COORDINATOR_URL", @default_coordinator_url)
           |> URI.parse() do
        %URI{scheme: "ws", host: host, port: port} ->
          {host, port}
      end

    children = [
      {Task.Supervisor, name: Script.Supervisor},
      Cohort.Supervisor,
      {Connection, id: id, host: host, port: port}
    ]

    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 5,
      name: Stressgrid.Generator.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end

  defp default_generator_id do
    {r, 0} = System.cmd("hostname", ["-s"])
    r |> String.trim()
  end
end
