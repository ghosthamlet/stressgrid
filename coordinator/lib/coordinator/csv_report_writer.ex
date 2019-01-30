defmodule Stressgrid.Coordinator.CsvReportWriter do
  @moduledoc false

  alias Stressgrid.Coordinator.{ReportWriter, CsvReportWriter}

  @behaviour ReportWriter

  @management_base "priv/management"
  @results_base "results"

  defstruct metrics_table: %{},
            utilization_table: %{},
            active_counts_table: %{}

  def init() do
    %CsvReportWriter{}
  end

  def write_hists(_, clock, %CsvReportWriter{metrics_table: metrics_table} = writer, hists) do
    row =
      hists
      |> Enum.filter(fn {_, hist} ->
        :hdr_histogram.get_total_count(hist) != 0
      end)
      |> Enum.map(fn {key, hist} ->
        mean = :hdr_histogram.mean(hist)
        stddev = :hdr_histogram.stddev(hist)
        [{key, mean}, {:"#{key}_stddev", stddev}]
      end)
      |> Enum.concat()
      |> Map.new()
      |> Map.merge(metrics_table |> Map.get(clock, %{}))

    %{writer | metrics_table: metrics_table |> Map.put(clock, row)}
  end

  def write_scalars(_, clock, %CsvReportWriter{metrics_table: metrics_table} = writer, scalars) do
    row =
      scalars
      |> Map.new()
      |> Map.merge(metrics_table |> Map.get(clock, %{}))

    %{writer | metrics_table: metrics_table |> Map.put(clock, row)}
  end

  def write_utilizations(
        _,
        clock,
        %CsvReportWriter{utilization_table: utilization_table} = writer,
        utilizations
      ) do
    utilization_count = Enum.count(utilizations)

    average_cpu =
      if utilization_count === 0 do
        0
      else
        (utilizations
         |> Enum.map(fn {_, %{cpu: cpu}} -> cpu end)
         |> Enum.sum()) / utilization_count
      end

    total_network_rx =
      utilizations
      |> Enum.map(fn {_, %{network_rx: network_rx}} -> network_rx end)
      |> Enum.sum()

    total_network_tx =
      utilizations
      |> Enum.map(fn {_, %{network_tx: network_tx}} -> network_tx end)
      |> Enum.sum()

    row =
      utilizations
      |> Enum.map(fn {generator, %{cpu: cpu, network_rx: network_rx, network_tx: network_tx}} ->
        [
          {:"#{generator}_cpu", cpu},
          {:"#{generator}_network_rx", network_rx},
          {:"#{generator}_network_tx", network_tx}
        ]
      end)
      |> Enum.concat()
      |> Map.new()
      |> Map.put(:average_cpu, average_cpu)
      |> Map.put(:total_network_rx, total_network_rx)
      |> Map.put(:total_network_tx, total_network_tx)

    %{writer | utilization_table: utilization_table |> Map.put(clock, row)}
  end

  def write_active_counts(
        _,
        clock,
        %CsvReportWriter{active_counts_table: active_counts_table} = writer,
        active_counts
      ) do
    values =
      active_counts
      |> Enum.map(fn {_, v} -> v end)

    total = values |> Enum.sum()

    row =
      active_counts
      |> Map.new()
      |> Map.put(:total, total)

    %{writer | active_counts_table: active_counts_table |> Map.put(clock, row)}
  end

  def finish(result_info, id, %CsvReportWriter{
        metrics_table: metrics_table,
        utilization_table: utilization_table,
        active_counts_table: active_counts_table
      }) do
    tmp_directory = Path.join([System.tmp_dir(), id])
    File.mkdir_p!(tmp_directory)

    write_csv(metrics_table, Path.join([tmp_directory, "metrics.csv"]))
    write_csv(utilization_table, Path.join([tmp_directory, "utilization.csv"]))
    write_csv(active_counts_table, Path.join([tmp_directory, "active_counts.csv"]))

    filename = "#{id}.tar.gz"
    directory = Path.join([Application.app_dir(:coordinator), @management_base, @results_base])
    File.mkdir_p!(directory)

    result_info =
      case System.cmd("tar", ["czf", Path.join(directory, filename), "-C", System.tmp_dir(), id]) do
        {_, 0} ->
          result_info |> Map.merge(%{"csv_url" => Path.join([@results_base, filename])})

        _ ->
          result_info
      end

    File.rm_rf!(Path.join([System.tmp_dir(), id]))

    result_info
  end

  defp write_csv(table, file_name) do
    keys =
      table
      |> Enum.reduce([], fn {_, row}, keys ->
        row
        |> Enum.reduce(keys, fn {key, _}, keys -> [key | keys] end)
        |> Enum.uniq()
      end)

    keys_string =
      keys
      |> Enum.map(&"#{&1}")
      |> Enum.join(",")

    io_data =
      ["clock,#{keys_string}\r\n"] ++
        (table
         |> Enum.map(fn {clock, row} ->
           values_string =
             keys
             |> Enum.map(fn key ->
               case row |> Map.get(key) do
                 nil ->
                   ""

                 value ->
                   "#{value}"
               end
             end)
             |> Enum.join(",")

           "#{clock},#{values_string}\r\n"
         end)
         |> Enum.to_list())

    File.write!(file_name, io_data)
  end
end
