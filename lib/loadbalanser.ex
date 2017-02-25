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
        Agent.start_link(fn -> [] end,  name: :tasks )
        Agent.start_link(fn -> [] end,  name: :employers)
        wait_for_separate_nodes()
    end

    def wait_for_separate_nodes do
        receive do
            {:pingme} -> Logger.info "PINGED!!!"
            {:register_task, pid}  ->
                Logger.info "Task registererd."
                Agent.update(:tasks , fn lst -> [pid | lst] end)
            {:add_employer, e} when is_list(e) ->
                Logger.info "Employers (#{e}) added."
                Agent.update(:employers , fn lst -> lst ++ e end)
            {:add_employer, e} ->
                Agent.update(:employers , fn lst -> [e | lst] end)
            :registration_finished ->
                Logger.info "Registration finished "
                         #  &(&1) is 'identity'
                         <> "(Task count: #{length Agent.get(:tasks , &(&1))})"
                distribute_employers_initial()
            anyoneelse ->
                IO.inspect anyoneelse
            after 20_000 ->
                Logger.info "On timeout (10 sec)"
                Logger.info "Registration finished "
                         #  &(&1) is 'identity'
                         <> "(Task count: #{length Agent.get(:tasks , &(&1))})"
                distribute_employers_initial()
        end
        # Remember: after all deals/balances/results
        # we come back to this function
        wait_for_separate_nodes()
   end

   def wait_for_results do
       receive do
           msg -> IO.inspect msg
       end
   end

    def distribute_employers_initial do
        tasks = Agent.get_and_update(:tasks,     fn l -> {l, []} end)
        empls = Agent.get_and_update(:employers, fn l -> {l, []} end)

        # We hope len tasks < than len employers
        # TODO: Shit: we just need to send each employer to different tasks
        # And we have to repeat tasks while employers do not come to an end
        Enum.reduce(empls, tasks, fn (e, []    ) -> [t|ts] = tasks
                                                    send t, {:employer, e}
                                                    ts
                                     (e, [t|ts]) -> send t, {:employer, e}
                                                    ts
                                  end)

        tasks |> Stream.each(fn t -> send t, {:deal_finished, tasks} end)
              |> Enum.to_list

        wait_for_results()
    end
end
