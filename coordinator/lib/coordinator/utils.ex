defmodule Stressgrid.Coordinator.Utils do
  def split_blocks(_, 0) do
    []
  end

  def split_blocks(blocks, split_size) do
    chunks =
      blocks
      |> Enum.map(fn block ->
        size = block |> Map.get(:size, 1)

        if size > split_size do
          1..split_size |> Enum.map(fn _ -> block |> Map.put(:size, trunc(size / split_size)) end)
        else
          if size > 0 do
            1..size |> Enum.map(fn _ -> block |> Map.put(:size, 1) end)
          else
            []
          end
        end
      end)
      |> Enum.concat()
      |> Enum.chunk_every(split_size)

    1..split_size
    |> Enum.map(fn i ->
      chunks
      |> Enum.map(fn chunk ->
        chunk |> Enum.at(i - 1)
      end)
      |> Enum.reject(fn
        nil -> true
        _ -> false
      end)
    end)
  end
end
