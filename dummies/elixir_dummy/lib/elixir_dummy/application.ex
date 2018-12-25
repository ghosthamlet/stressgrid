defmodule Dummy.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {"/", Dummy, %{}}
         ]}
      ])

    children = [
      %{
        id: :dummy,
        start:
          {:cowboy, :start_clear,
           [
             :dummy,
             %{max_connections: 999_999, socket_opts: [port: 5000]},
             %{max_keepalive: 1_000, env: %{dispatch: dispatch}}
           ]},
        restart: :permanent,
        shutdown: :infinity,
        type: :supervisor
      }
    ]

    opts = [strategy: :one_for_one, name: Dummy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
