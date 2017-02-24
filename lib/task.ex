defmodule Tasks do

  def start filename, server do
    employers = initialize filename, server
    initial_deal_employers employers
  end

  defp connect_to_server_node server, time \\ 0 do
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

  defp initialize filename, server do

    data = load_data filename

    manager = connect_to_server_node server
    manager |> send {:register_task, self()}
    manager |> send {:add_employer, data[:employers]}

    {:ok, employers} = Agent.start_link fn -> [] end

    employers
  end

  defp initial_deal_employers employers do
     receive do
       {:employer, skill} -> Agent.update(employers, fn lst -> [skill|lst] end)
       {:deal_finished}   -> IO.puts "#{self()} received :deal_finished"
     end
  end

  def load_data filename do
    {:ok, list} = filename |> File.read! |> JSON.decode
    parse_data list
  end

  def parse_data kw do
    Keyword.new |> Keyword.put( :employers, kw["employers"] )
                |> Keyword.put( :task, kw["task"] )
  end

end
