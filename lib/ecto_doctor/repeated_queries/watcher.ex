defmodule EctoDoctor.RepeatedQueries.Watcher do
  @moduledoc false

  # Owns the scan tables and drops the scans of processes that die before finishing them

  use GenServer

  alias EctoDoctor.RepeatedQueries.Store

  @spec start() :: GenServer.on_start()
  def start, do: GenServer.start(__MODULE__, nil, name: __MODULE__)

  @spec stop() :: :ok
  def stop do
    if Process.whereis(__MODULE__), do: GenServer.stop(__MODULE__)
    :ok
  end

  @spec watch(pid()) :: :ok
  def watch(pid), do: GenServer.cast(__MODULE__, {:watch, pid})

  @impl GenServer
  def init(nil) do
    Store.create_tables()
    {:ok, MapSet.new()}
  end

  # A request process or LiveView watched once stays watched for every later unit
  @impl GenServer
  def handle_cast({:watch, pid}, watched) do
    if MapSet.member?(watched, pid) do
      {:noreply, watched}
    else
      Process.monitor(pid)
      {:noreply, MapSet.put(watched, pid)}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, watched) do
    Store.drop(pid)
    {:noreply, MapSet.delete(watched, pid)}
  end

  def handle_info(_message, watched), do: {:noreply, watched}
end
