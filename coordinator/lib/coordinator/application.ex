defmodule Stressgrid.Coordinator.Application do
  @moduledoc false

  use Application
  require Logger

  alias Stressgrid.Coordinator.{
    GeneratorConnection,
    GeneratorRegistry,
    Reporter,
    Scheduler,
    CsvReportWriter,
    CloudWatchReportWriter,
    ManagementConnection
  }

  def start(_type, _args) do
    generators_port = System.get_env() |> Map.get("PORT", "9696") |> String.to_integer()
    management_port = System.get_env() |> Map.get("PORT", "8000") |> String.to_integer()

    writers =
      [CsvReportWriter.init()] ++
        case cloudwatch_region() do
          nil ->
            []

          cloudwatch_region ->
            [CloudWatchReportWriter.init(cloudwatch_region)]
        end

    children = [
      {Registry, keys: :duplicate, name: ManagementConnection},
      GeneratorRegistry,
      {Reporter, writers: writers},
      Scheduler,
      cowboy_sup(:generators_listener, generators_port, generators_dispatch()),
      cowboy_sup(:management_listener, management_port, management_dispatch())
    ]

    Logger.info("Listening for generators on port #{generators_port}")
    Logger.info("Listening for management on port #{management_port}")

    opts = [strategy: :one_for_one, name: Stressgrid.Coordinator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cowboy_sup(id, port, dispatch) do
    %{
      id: id,
      start: {:cowboy, :start_clear, [id, [port: port], %{env: %{dispatch: dispatch}}]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  defp generators_dispatch do
    :cowboy_router.compile([{:_, [{"/", GeneratorConnection, %{}}]}])
  end

  defp management_dispatch do
    :cowboy_router.compile([
      {:_,
       [
         {"/", :cowboy_static,
          {:priv_file, :coordinator, "management/index.html",
           [{:mimetypes, :cow_mimetypes, :all}]}},
         {"/ws", ManagementConnection, %{}},
         {"/[...]", :cowboy_static,
          {:priv_dir, :coordinator, "management", [{:mimetypes, :cow_mimetypes, :all}]}}
       ]}
    ])
  end

  defp cloudwatch_region do
    System.get_env()
    |> Map.get("CW_REGION")
  end
end
