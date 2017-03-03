defmodule Manager do
    use GenServer

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
    @timeout 25_000

    def start_link do
        name = Application.get_env(:loadbalanser, :manager_p_name)
        {:ok, pid} = GenServer.start_link(__MODULE__, []) # state is tasks
        :global.register_name(name, pid)
    end

    def init(state) do
        Agent.start_link(fn -> [] end,  name: :employers)
        {:ok, state}
    end

    def handle_cast {:pingme}, state do
        Logger.info "PINGED!!!"
        {:noreply, state, @timeout}
    end

    def handle_cast {:register_task, pid}, tasks do
        Logger.info "Task registererd."
        {:noreply, [pid | tasks], @timeout}
    end

    def handle_cast({:add_employer, e}, state) when is_list(e) do
           Logger.info "Employers (#{inspect e}) added."
           Agent.update(:employers , fn lst -> lst ++ e end)
           {:noreply, state, @timeout}
    end

    def handle_cast {:add_employer, e}, state do
        Agent.update(:employers , fn lst -> [e | lst] end)
        {:noreply, state, @timeout}
    end

    def handle_cast :registration_finished, tasks do
        Logger.info "Registration finished "
                 #  &(&1) is 'identity'
                 <> "(Task count: #{length tasks})"
        distribute_employers_initial(tasks)
        {:stop, :normal, []}
    end

    def handle_info :timeout, tasks do
        Logger.info "On timeout (10 sec)"
        Logger.info "Registration finished "
                 #  &(&1) is 'identity'
                 <> "(Task count: #{length tasks})"
        distribute_employers_initial(tasks)
        {:stop, :normal, []}
    end

    def distribute_employers_initial tasks do
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
        # Little asyncronus
        [fst | oth] = tasks
        send fst, {:deal_finished, tasks}
        Process.sleep(300)
        oth |> Stream.each(fn t -> send t, {:deal_finished, tasks} end)
            |> Enum.to_list
    end
end
