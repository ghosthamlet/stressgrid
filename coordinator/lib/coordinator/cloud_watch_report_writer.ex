defmodule Stressgrid.Coordinator.CloudWatchReportWriter do
  @moduledoc false

  alias Stressgrid.Coordinator.{ReportWriter, CloudWatchReportWriter}

  @behaviour ReportWriter

  defstruct [:region]

  def init(region) do
    %CloudWatchReportWriter{region: region}
  end

  def write_hists(id, _, %CloudWatchReportWriter{region: region}, hists) do
    put_metric_data(
      region,
      hists
      |> Enum.reduce([], fn {key, hist}, acc ->
        if :hdr_histogram.get_total_count(hist) != 0 do
          count = :hdr_histogram.get_total_count(hist)
          sum = :hdr_histogram.mean(hist) * count
          max = :hdr_histogram.max(hist)
          min = :hdr_histogram.min(hist)
          [{:statistic, key, key_unit(key), count, sum, max, min, [run: id]} | acc]
        else
          acc
        end
      end)
    )
  end

  def write_scalars(id, _, %CloudWatchReportWriter{region: region}, scalars) do
    put_metric_data(
      region,
      scalars
      |> Enum.map(fn {key, value} ->
        {:scalar, key, key_unit(key), value, [run: id]}
      end)
    )
  end

  def write_utilizations(_, _, _, _) do
    :ok
  end

  def write_active_counts(id, _, %CloudWatchReportWriter{region: region}, active_counts) do
    total_active_count =
      active_counts
      |> Enum.map(fn {_, active_count} -> active_count end)
      |> Enum.sum()

    put_metric_data(
      region,
      active_counts
      |> Enum.map(fn {generator, active_count} ->
        {:scalar, :active_count, :count, active_count, [run: id, generator: generator]}
      end)
      |> Enum.concat([
        {:scalar, :total_active_count, :count, total_active_count, [run: id]}
      ])
    )
  end

  def finish(result_info, id, %CloudWatchReportWriter{region: region}) do
    cw_url =
      "https://#{region}.console.aws.amazon.com/cloudwatch/home" <>
        "?region=#{region}#metricsV2:graph=~();search=#{id}"

    result_info |> Map.merge(%{"cw_url" => cw_url})
  end

  def put_metric_data(region, datum) do
    params = %{
      "Action" => "PutMetricData",
      "Version" => "2010-08-01",
      "Namespace" => "Stressgrid"
    }

    {_, params} =
      datum
      |> Enum.reduce({1, params}, fn
        {:scalar, name, unit, value, dims}, {i, params} ->
          prefix = "MetricData.member.#{i}"

          params =
            params
            |> Map.merge(%{
              "#{prefix}.MetricName" => name |> Atom.to_string() |> Macro.camelize(),
              "#{prefix}.Unit" => unit_to_data(unit),
              "#{prefix}.Value" => value
            })

          {i + 1,
           params
           |> Map.merge(dim_params(prefix, dims))}

        {:statistic, name, unit, count, sum, max, min, dims}, {i, params} ->
          prefix = "MetricData.member.#{i}"

          params =
            params
            |> Map.merge(%{
              "#{prefix}.MetricName" => name |> Atom.to_string() |> Macro.camelize(),
              "#{prefix}.Unit" => unit_to_data(unit),
              "#{prefix}.StatisticValues.SampleCount" => count,
              "#{prefix}.StatisticValues.Sum" => sum,
              "#{prefix}.StatisticValues.Maximum" => max,
              "#{prefix}.StatisticValues.Minimum" => min
            })

          {i + 1,
           params
           |> Map.merge(dim_params(prefix, dims))}
      end)

    %{status_code: 200} =
      %ExAws.Operation.Query{
        path: "/",
        params: params,
        service: :monitoring,
        action: :put_metric_data,
        parser: &ExAws.Cloudwatch.Parsers.parse/2
      }
      |> ExAws.request!(region: region)

    :ok
  end

  defp dim_params(prefix, dims) do
    {_, dim_params} =
      dims
      |> Enum.reduce({1, %{}}, fn {name, value}, {k, params} ->
        dim_prefix = "#{prefix}.Dimensions.member.#{k}"

        {k + 1,
         params
         |> Map.merge(%{
           "#{dim_prefix}.Name" => name |> Atom.to_string() |> Macro.camelize(),
           "#{dim_prefix}.Value" => value
         })}
      end)

    dim_params
  end

  defp unit_to_data(:count), do: "Count"
  defp unit_to_data(:count_per_second), do: "Count/Second"
  defp unit_to_data(:percent), do: "Percent"
  defp unit_to_data(:us), do: "Microseconds"

  defp key_unit(key) do
    key_s = key |> Atom.to_string()

    if Regex.match?(~r/count_per_second$/, key_s) do
      :count_per_second
    else
      if Regex.match?(~r/count$/, key_s) do
        :count
      else
        if Regex.match?(~r/us$/, key_s) do
          :us
        else
          :count
        end
      end
    end
  end
end
