defmodule TaskSpec do
    defstruct task: -1, employers: [], other_tasks: []
end

defmodule Tasks do
    require Logger

    def start filename, server do
        task_data = initialize filename, server
        initial_deal_employers(task_data)
    end

    defp initialize filename, server do
        task_data = load_data filename

        manager = connect_to_server_node server
        manager |> send {:register_task, self()}
        manager |> send {:add_employer, task_data.employers}

        task_data
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
                updated = %{task_data | employers: [empl|task_data.employers]}
                initial_deal_employers updated
            {:deal_finished, tasks} ->
                empls = task_data.employers
                Logger.info "Received :deal_finished.\n"
                         <> "List of empls: #{inspect empls}"
                task = task_data.task
                sorted_empls = if Enum.sum(empls) > task do
                                   empls |> Enum.sort
                               else
                                   empls |> Enum.sort |> Enum.reverse
                               end
                updated = %{task_data | other_tasks: tasks}
        end
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
