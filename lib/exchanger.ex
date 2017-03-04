defmodule Exchanger do
    use GenFSM
    alias TaskProto, as: Tasks

    require Logger

    @check_offers_timeout         1_000
    @wait_agreement_timeout       1_000
    @make_offer_timeout           1_000
    @check_offers_finally_timeout 2_000

    def start_link filename, server do
        {manager, task_data} = initialize filename, server
        {:ok, pid} = GenFSM.start_link(__MODULE__, task_data)
        GenServer.cast(manager, {:register_task, pid})
        pid
    end

    defp initialize filename, server do
        task_data = load_data filename

        manager = connect_to_server_node server
        GenServer.cast(manager, {:add_employer, task_data.employers})
        # We sent all our employers to manager
        # So now we have zero employers
        {manager, %{task_data | employers: []}}
    end

    defp connect_to_server_node server, time \\ 1 do
        IO.puts "Try to connect #{time} time."
        is_ok = Node.connect server
        if is_ok do
            manager = Application.get_env(:loadbalanser, :manager_p_name)
                     |> :global.whereis_name
            case manager do
                :undefined ->
                  Process.sleep(1000 + 100 * time)
                  connect_to_server_node(server, time + 1)
                pid        ->
                  IO.puts "Connection succesfull."
                  pid
            end
        else
            IO.puts "Connection failed. Try again..."
            connect_to_server_node(server, time + 1)
        end
    end

    def init(task_data) do
        {:ok, :initial_deal_employers, task_data}
        # send self(), :piy
        # {:ok, :piy, task_data, @empl_deal_timeout}
    end

    def initial_deal_employers({:employer, empl}, task_data) do
        Logger.info "Employer (#{empl}) added"
        updated = task_data |> Tasks.push_employer(empl)
        {:next_state, :initial_deal_employers, updated}
    end

    def initial_deal_employers({:deal_finished, tasks}, task_data) do
        empls = task_data.employers
        coef = task_data.skill_sum / task_data.task
        Logger.info "Received :deal_finished.\n"
                 <> "List of empls: #{inspect empls}\n"
                 <> "Task: #{task_data.task} (#{coef})"
        updated = task_data |> Tasks.push_remaining_tasks(tasks)
        try_exchange(updated)
    end

    def initial_deal_employers(:timeout, task_data) do
        Logger.info "On timeout"
        {:next_state, :initial_deal_employers, task_data}
    end

    def initial_deal_employers(etc, task_data) do
        Logger.info "initial_deal_employers(#{inspect etc})"
        {:next_state, :initial_deal_employers, task_data}
    end

    def try_exchange task_data do
        Logger.info "try_exchange"
        r = task_data |> Tasks.pop_remaining_task
        if is_nil(r) do
            Logger.info "We tried all tasks!"
            # check_offers_finally(task_data)
            {:next_state, :check_offers_finally,
             task_data, @check_offers_finally_timeout}
        else
            {t, without_task} = r
            Logger.info "Only #{length without_task.remaining_tasks} tasks left"
            if t != self() do
                # send t, {:go_exchange, self(), without_task}
                GenFSM.send_event(t, {:go_exchange, without_task})
                {:next_state, :wait_agreement, without_task,
                 @wait_agreement_timeout}
                 # receive .....
            else
                try_exchange(without_task)
            end
        end
    end

    def wait_agreement(:no, without_task) do
        Logger.info "We don't go exchange"
        # check_offers(without_task)
        {:next_state, :check_offers, without_task, @check_offers_timeout}
    end

    def wait_agreement(:timeout, without_task) do
        # check_offers(without_task)
        {:next_state, :check_offers, without_task, @check_offers_timeout}
    end

    def wait_agreement(msg, without_task) do
        IO.puts "Ignored #{inspect msg}"
        # itself.(itself)
        {:next_state,
         :wait_agreement,
         without_task,
         @wait_agreement_timeout}
    end

    def wait_agreement({:go, new_data}, from, _) do
        Logger.info "go exchenge (is's agrement)!"
        GenFSM.send_event(from, :done)
        {:next_state, :check_offers, new_data,
        @check_offers_timeout}
    end

    def wait_agreement({:go_exchange, _task}, from, without_task) do
        Logger.info "I'm busy"
        # send pid, :busy
        # itself.(itself)
        GenFSM.send_event(from, :busy)
        {:next_state,
        :wait_agreement, without_task,
        @wait_agreement_timeout}
    end

    def wait_agreement(:busy, from, without_task) do
        Logger.info "It's busy"
        Process.sleep(100)
        # check_offers(task_data)
        task_data = without_task
                 |> Tasks.push_remaining_tasks([from])
        {:next_state, :check_offers,
        task_data, @check_offers_timeout}
    end

    def check_offers({:go_exchange, other_data}, from, task_data) do
        Logger.info "check_offers"
        Logger.info "Received offer "
                 <> "(#{List.first task_data.employers} and"
                 <> " #{List.first other_data.employers})."
        if should_exchange?(task_data, other_data) do
            Logger.info "We should exchange"
            {new, oth_new} = Tasks.exchange(task_data, other_data)
            # send pid, {:go, self(), oth_new}
            # receive ...
            GenFSM.send_event(from, {:go, oth_new})
            {:next_state,
             :make_offer, {task_data, new},
             @make_offer_timeout}
        else
            Logger.info "We shouldn't exchange"
            # send pid, :no
            GenFSM.send_event(from, :no)
            try_exchange(task_data)
        end
    end

    def check_offers(:timeout, task_data), do: try_exchange(task_data)

    def check_offers(msg, task_data) do
        IO.puts "Ignored #{inspect msg}"
        #    IO.puts "Ignored #{inspect msg}"
        {:next_state, :check_offers, task_data, @check_offers_timeout}
    end

    def make_offer(:done, {_, new}) do
        Logger.info "Exchange finished."
        try_exchange(new)
    end

    def make_offer(:timeout,  {task_data, _}) do
        # Maybe wrong
        try_exchange(task_data)
    end

    def make_offer msg, {task_data, new} do
        IO.puts "Ignored #{inspect msg}"
        # We shouldn't update timer
        {:next_state,
         :make_offer, {task_data, new},
         @make_offer_timeout
        }
    end

    def make_offer({:go_exchange, _data}, from, {task_data, new}) do
        # send pid, :busy
        # We shouldn't update timer
        GenFSM.send_event(from, :busy)
        {:next_state,
         :make_offer, {task_data, new},
         @make_offer_timeout
        }
    end

    def check_offers_finally({:go_exchange, other_data}, from, task_data) do
        Logger.info "Received offer "
                 <> "(#{List.first task_data.employers} and"
                 <> " #{List.first other_data.employers})."
        if should_exchange?(task_data, other_data) do
            {new, oth_new} = Tasks.exchange(task_data, other_data)
            # send pid, {:go, self(), oth_new}
            GenFSM.send_event(from, {:go, oth_new})
            {:next_state,
             :make_offer_finally,
             {task_data, new},
             @check_offers_timeout}
            # receive ....
        else
            # send pid, :no
            # check_offers_finally(task_data)
            GenFSM.send_event(from, :no)
            {:next_state,
             :check_offers_finally, task_data,
             @check_offers_finally_timeout}
        end
    end

    def check_offers_finally :timeout, task_data do
        job_is_done(task_data)
    end

    def make_offer_finally :done, {_, new_data} do
        Logger.info "Exchange finished."
        # check_offers_finally(new)
        {:next_state, :check_offers_finally,
        new_data, @check_offers_finally_timeout}
    end

    def make_offer_finally :timeout, {old, _} do
        Logger.info "Exchange timeout."
        {:next_state, :check_offers_finally,
        old, @check_offers_finally_timeout}
    end

    def make_offer_finally msg, {old, new} do
        Logger.info "Ignored: #{inspect msg}"
        # check_offers_finally(new)
        # We shouldn't update timer
        {:next_state,
        :make_offer_finally, {old, new},
        @make_offer_timeout}
    end

    def handle_info info, statename, _statedata do
        IO.puts "HANDLE_INFO"
        IO.inspect(info)
        IO.inspect(statename)
    end

    def job_is_done task_data do
        coef = task_data.skill_sum / task_data.task
        Logger.info "I'm DONE."
                 <> "List of empls: #{inspect task_data.employers}\n"
                 <> "Task: #{task_data.task} (#{coef})"
        {:stop, :normal, task_data}
    end

    defp should_exchange? first, second do
        {first_new, second_new} = Tasks.exchange(first, second)

        old_disbalance = [first, second]
                        |> Enum.map(&Tasks.disbalance &1)
                        |> Enum.sum

        new_disbalance = [first_new, second_new]
                        |> Enum.map(&Tasks.disbalance &1)
                        |> Enum.sum

        new_disbalance < old_disbalance
    end

    defp load_data filename do
        {:ok, list} = filename |> File.read! |> JSON.decode
        parse_data list
    end

    defp parse_data kw do
        %TaskSpec{
            employers: kw["employers"],
            task:      kw["task"]
        }
    end
end
