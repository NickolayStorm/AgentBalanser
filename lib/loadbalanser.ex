defmodule Manager do
  require Logger
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
      {:pingme} -> Logger.log 1, "PINGED!!!"
      {:register_task, pid}  ->
        Logger.log 1, "Task registererd."
        Agent.update(:tasks_store, fn lst -> [pid | lst] end)
      {:add_employer, e} when is_list(e) ->
        Logger.log 1, "Employers (#{e}) added."
        Agent.update(:tasks_store, fn lst -> lst ++ e end)
      {:add_employer, e} ->
        Agent.update(:tasks_store, fn lst -> [e | lst] end)
      {:registation_finished} ->
        Logger.log 1, "Registration finished "
             <> "(Task count: #{length Agent.get(:tasks_store, fn l -> l end)})"
      anyoneelse -> IO.inspect anyoneelse
    end
    wait_for_separate_nodes()
  end
end
