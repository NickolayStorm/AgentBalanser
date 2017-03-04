defmodule Exchanger do
    require Logger
    alias TaskProto, as: Tasks

    def start filename, server do
        task_data = initialize filename, server
        initial_deal_employers(task_data)
    end

    defp initialize filename, server do
        task_data = load_data filename

        manager = connect_to_server_node server
        GenServer.cast(manager, {:register_task, self()})
        GenServer.cast(manager, {:add_employer, task_data.employers})

        # We sent all our employers to manager
        # So now we have zero employers
        %{task_data | employers: []}
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

    defp initial_deal_employers task_data do
        receive do
            {:employer, empl} ->
                Logger.info "Employer (#{empl}) added"
                updated = task_data |> Tasks.push_employer(empl)
                initial_deal_employers updated
            {:deal_finished, tasks} ->
                empls = task_data.employers
                coef = task_data.skill_sum / task_data.task
                Logger.info "Received :deal_finished.\n"
                         <> "List of empls: #{inspect empls}\n"
                         <> "Task: #{task_data.task} (#{coef})"
                updated = task_data |> Tasks.push_remaining_tasks(tasks)
                try_exchange(updated)
        end
    end

    def try_exchange task_data do
        Logger.info "try_exchange"
        r = task_data |> Tasks.pop_remaining_task
        if is_nil(r) do
            Logger.info "We tried all tasks!"
            check_offers_finally(task_data)
        else
            {t, without_task} = r
            Logger.info "Only #{length without_task.remaining_tasks} tasks left"
            if t != self() do
                send t, {:go_exchange, self(), without_task}
                wait_agreement = fn itself ->
                            receive do
                                {:go, t, new_data} ->
                                    Logger.info "go exchenge (is's agrement)!"
                                    send t, :done
                                    check_offers(new_data)
                                :no ->
                                    Logger.info "We don't go exchange"
                                    check_offers(without_task)
                                {:go_exchange, pid, _task} ->
                                    Logger.info "I'm busy"
                                    send pid, :busy
                                    itself.(itself)
                                :busy ->
                                    Logger.info "It's busy"
                                    Process.sleep(100)
                                    check_offers(task_data)
                                msg ->
                                    IO.puts "Ignored #{inspect msg}"
                                    itself.(itself)
                            after
                                1_000 ->
                                    check_offers(without_task)
                            end
                        end
                wait_agreement.(wait_agreement)
            else
                try_exchange(without_task)
            end
        end
    end

    def check_offers task_data do
        Logger.info "check_offers"
        receive do
            {:go_exchange, pid, other_data} ->
                Logger.info "Received offer "
                         <> "(#{List.first task_data.employers} and"
                         <> " #{List.first other_data.employers})."
                if should_exchange?(task_data, other_data) do
                    Logger.info "We should exchange"
                    {new, oth_new} = Tasks.exchange(task_data, other_data)
                    send pid, {:go, self(), oth_new}
                    receive do
                        :done ->
                            Logger.info "Exchange finished."
                            try_exchange(new)
                        {:go_exchange, pid, _data} ->
                            send pid, :busy
                         msg ->
                             IO.puts "Ignored #{inspect msg}"

                    after 1_000 ->
                            Logger.info "Exchange timeout."
                            try_exchange(task_data)
                    end
                else
                    Logger.info "We shouldn't exchange"
                    send pid, :no
                    try_exchange(task_data)
                end
            msg ->
                IO.puts "Ignored #{inspect msg}"

        after 1_000 -> try_exchange(task_data)
        end
    end

    def check_offers_finally task_data do
        receive do
            {:go_exchange, pid, other_data} ->
                Logger.info "Received offer "
                         <> "(#{List.first task_data.employers} and"
                         <> " #{List.first other_data.employers})."
                if should_exchange?(task_data, other_data) do
                    {new, oth_new} = Tasks.exchange(task_data, other_data)
                    send pid, {:go, self(), oth_new}
                    receive do
                        :done ->
                            Logger.info "Exchange finished."
                            check_offers_finally(new)
                    after 1_000 ->
                            Logger.info "Exchange timeout."
                            check_offers_finally(task_data)
                    end
                else
                    send pid, :no
                    check_offers_finally(task_data)
                end
        after 2_000 ->
            job_is_done task_data
        end
    end

    def job_is_done task_data do
        coef = task_data.skill_sum / task_data.task
        Logger.info "I'm DONE."
                 <> "List of empls: #{inspect task_data.employers}\n"
                 <> "Task: #{task_data.task} (#{coef})"
    end

    def should_exchange? first, second do
        {first_new, second_new} = Tasks.exchange(first, second)

        old_disbalance = [first, second]
                        |> Enum.map(&Tasks.disbalance &1)
                        |> Enum.sum

        new_disbalance = [first_new, second_new]
                        |> Enum.map(&Tasks.disbalance &1)
                        |> Enum.sum

        new_disbalance < old_disbalance
    end

    def perfect_state _data do
        Logger.info "Perfect state"
        sleep = fn itself ->
                    receive do
                        msg -> IO.inspect msg
                    end
                    itself.()
                end
        sleep.(sleep)
    end

    def load_data filename do
        {:ok, list} = filename |> File.read! |> JSON.decode
        parse_data list
    end

    def parse_data kw do
        %TaskSpec{
            employers: kw["employers"],
            task:      kw["task"]
        }
    end
end
