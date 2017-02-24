defmodule Manager do
  @moduledoc """
  Documentation for Manager.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Manager.hello
      :world

  """

  def start do
    name = Application.get_env(:loadbalanser, :manager_p_name)
    :global.register_name(name, self())
    Agent.start_link(fn -> [] end,  name: :tasks_store)
    wait_for_separate_nodes()
  end

  def wait_for_separate_nodes do
    receive do
      {:pingme} -> IO.puts "PINGED!!!"
      {:register_task, pid}  ->
        IO.puts "Task registererd."
        Agent.update(:tasks_store, fn lst -> [pid | lst] end)
      {:add_employer, e} when is_list(e) ->
        IO.puts "Employers (#{e}) added."
        Agent.update(:tasks_store, fn lst -> lst ++ e end)
      {:add_employer, e} ->
        Agent.update(:tasks_store, fn lst -> [e | lst] end)
      {:registation_finished} ->
        IO.puts "Registration finished "
             <> "(Task count: #{length Agent.get(:tasks_store, fn l -> l end)})"
      anyoneelse -> IO.inspect anyoneelse
    end
    wait_for_separate_nodes()
  end

  # def make_agents data do
  #   # Enumerable.for x <- data[:employers], do: IO.puts "Task #{x}"
  #   Enum.each(data[:employers], fn e -> IO.puts "Employer #{e}" end)
  # end

  def load_data filename do
    {:ok, list} = filename |> File.read! |> JSON.decode
    parse_data list
  end

  def parse_data kw do
    Keyword.new |> Keyword.put( :tasks,     kw["tasks"]    )
                |> Keyword.put( :employers, kw["employers"] )
  end
  def hello do
    :world
  end
end
