defmodule Stressgrid.Coordinator.ReportWriter do
  @callback write_hists(String.t(), Integer.t(), Writer.t(), List.t()) :: :ok
  @callback write_scalars(String.t(), Integer.t(), Writer.t(), List.t()) :: :ok
  @callback write_utilizations(String.t(), Integer.t(), Writer.t(), List.t()) :: :ok
  @callback write_active_counts(String.t(), Integer.t(), Writer.t(), List.t()) :: :ok
  @callback finish(Map.t(), String.t(), Writer.t()) :: Map.t()
end
