defmodule Commands do
    use GenFSM
    require Logger

    @max_empls 3
    @timeout 10_000

    def start_link filename, server do
        manager = initialize filename, server
        {:ok, pid} = GenFSM.start_link(__MODULE__, [])#, [{:debug, [:log, :trace]}])
        GenServer.cast(manager, {:register_task, pid})
        pid
    end

    defp initialize filename, server do
        task_data = load_data filename
        manager = connect_to_server_node server
        GenServer.cast(manager, {:add_employer, task_data.employers})
        manager
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
                  Agent.start_link(fn -> pid end, name: :manager)
                  IO.puts "Connection succesfull."
                  pid
            end
        else
            IO.puts "Connection failed. Try again..."
            connect_to_server_node(server, time + 1)
        end
    end

    def init(_) do
        {:ok, :wait_employers, [], @timeout}
    end

    def wait_employers({:empls, empls}, _data) do
        Logger.info "received employers"
        empls |> Enum.map(fn e ->
            GenFSM.send_event(e, {:invite, self()}) end)
        {
            :next_state, :wait_agreement,
            [],
            @timeout
        }
    end

    def wait_employers(:timeout, data) do
        {
            :next_state, :wait_employers,
            data,
            @timeout
        }
    end

    def wait_agreement({:go, employer, from}, empls) do
        if length(empls) < @max_empls do
            GenFSM.send_event(from, {:ok, self()})
            {
                :next_state, :wait_agreement,
                [employer | empls],
                @timeout
            }
        else
            GenFSM.send_event(from, {:no, self()})
            {
                :next_state, :wait_agreement,
                empls,
                @timeout
            }
        end
    end

    def wait_agreement(:timeout, empls) do
        Logger.info "Wait agreement timeout"
        task_data = %TaskSpec{
                    employers: empls
                }
        ex = Exchanger.start_link(task_data)
        # Logger.info "Before agent update"
        Agent.update({:global, :tasks}, fn lst -> [ex | lst] end)
        Logger.info "Inintial command finished"
        {:stop, :normal, empls}
    end

    def handle_sync_event(:send_me_list, _from, state, data) do
        Logger.info "Sending list"
        # {reply,Reply,NextStateName,NewStateData,Timeout}
        {:reply, data, state, data, @timeout}
    end

    defp load_data filename do
        {:ok, list} = filename |> File.read! |> JSON.decode
        parse_data list
    end

    defp parse_data kw do
        emp_lst = kw["employers"]
        empls = Enum.map(emp_lst, fn dct ->
            %EmployerData{
                sql: dct["sql"],
                frontend: dct["frontend"],
                backend: dct["backend"]
            }
        end)
        %TaskSpec{
            employers: empls
        }
    end

end
