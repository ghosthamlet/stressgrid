defmodule Stressgrid.Coordinator.CsvReportWriter do
  @moduledoc false

  alias Stressgrid.Coordinator.{ReportWriter, CsvReportWriter}

  @behaviour ReportWriter

  @management_base "priv/management"
  @results_base "results"

  def init() do
    CsvReportWriter
  end

  def write_hists(id, clock, _, hists) do
    hists
    |> Enum.each(fn {key, hist} ->
      if :hdr_histogram.get_total_count(hist) != 0 do
        file_name = Path.join([ensure_temporary_directory(id), "#{key}.csv"])
        mean = :hdr_histogram.mean(hist)
        stddev = :hdr_histogram.stddev(hist)

        if not File.exists?(file_name) do
          File.write!(file_name, "clock,#{key},#{key}_s\r\n", [:append])
        end

        File.write!(file_name, "#{clock},#{mean},#{stddev}\r\n", [:append])
      end
    end)
  end

  def write_scalars(id, clock, _, scalars) do
    scalars
    |> Enum.each(fn {key, value} ->
      file_name = Path.join([ensure_temporary_directory(id), "#{key}.csv"])

      if not File.exists?(file_name) do
        File.write!(file_name, "clock,#{key}\r\n", [:append])
      end

      File.write!(file_name, "#{clock},#{value}\r\n", [:append])
    end)
  end

  def write_utilizations(id, clock, _, utilizations) do
    file_name = Path.join([ensure_temporary_directory(id), "utilization.csv"])

    if not File.exists?(file_name) do
      keys =
        utilizations
        |> Enum.map(fn {key, _} -> ["#{key}_cpu", "#{key}_network_rx", "#{key}_network_tx"] end)
        |> Enum.concat()
        |> Enum.join(",")

      File.write!(file_name, "clock,#{keys}\r\n", [:append])
    end

    values =
      utilizations
      |> Enum.map(fn {_, %{cpu: cpu, network_rx: network_rx, network_tx: network_tx}} ->
        ["#{cpu}", "#{network_rx}", "#{network_tx}"]
      end)
      |> Enum.concat()
      |> Enum.join(",")

    File.write!(file_name, "#{clock},#{values}\r\n", [:append])
  end

  def write_active_counts(id, clock, _, active_counts) do
    file_name = Path.join([ensure_temporary_directory(id), "active_counts.csv"])

    if not File.exists?(file_name) do
      keys =
        active_counts
        |> Enum.map(fn {key, _} -> "#{key}" end)
        |> Enum.join(",")

      File.write!(file_name, "clock,#{keys}\r\n", [:append])
    end

    values =
      active_counts
      |> Enum.map(fn {_, v} -> "#{v}" end)
      |> Enum.join(",")

    File.write!(file_name, "#{clock},#{values}\r\n", [:append])
  end

  def finish(result_info, id, _) do
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

  defp ensure_temporary_directory(id) do
    directory = Path.join([System.tmp_dir(), id])
    File.mkdir_p!(directory)
    directory
  end
end
