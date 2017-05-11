defmodule Exchanger do
    use GenFSM
    alias TaskProto, as: Tasks

    require Logger

    @check_offers_timeout         1_000
    @wait_agreement_timeout       1_000
    @make_offer_timeout           1_000
    @check_offers_finally_timeout 2_000

    def start_link task_data do
        Logger.info "Exchanger.start_link start"
        {:ok, pid} = GenFSM.start_link(__MODULE__, task_data) #, [{:debug, [:log, :trace]}])
        Logger.info "Exchanger.start_link finish"
        pid
    end

    def init(task_data) do
        Logger.info "Exchanger.init"
        {:ok, :wait_send_processes, task_data, 4_000}
    end

    def wait_send_processes(:timeout, task_data) do
        Logger.info "On timeout"
        tasks = Agent.get_and_update({:global, :tasks}, fn lst -> {lst, lst} end)
        Logger.info(inspect tasks)
        Logger.info "wait_send_proc: #{inspect task_data}"
        updated = task_data |> Tasks.push_remaining_tasks tasks
        updated = %{updated | all_tasks: tasks}
        Logger.info "wait_send_proc: #{inspect updated}"
        # {:next_state, :initial_deal_employers, task_data}
        try_exchange(updated)
    end

    def wait_send_processes({:go_exchange, from, _task}, data) do
        GenFSM.send_event(from, {:busy, self()})
        {:next_state, :wait_send_processes, data, 0}
    end

    def try_exchange task_data do
        Logger.info "try_exchange"
        r = task_data |> Tasks.pop_remaining_task
        Logger.info "try_exchange: #{inspect r}"
        if is_nil(r) do
            Logger.info "We tried all tasks!"
            {:next_state, :check_offers_finally,
             task_data, @check_offers_finally_timeout}
        else
            {t, without_task} = r
            Logger.info "Only #{length(without_task.remaining_tasks)+1} tasks left"
            Logger.info "try_exchange #{inspect without_task}"
            if t != self() do
                GenFSM.send_event(t, {:go_exchange, self(), without_task})
                {:next_state, :wait_agreement, without_task,
                 @wait_agreement_timeout}
            else
                try_exchange(without_task)
            end
        end
    end

    def wait_agreement(:no, without_task) do
        Logger.info "We don't go exchange"
        {:next_state, :check_offers, without_task, @check_offers_timeout}
    end

    def wait_agreement(:timeout, without_task) do
        {:next_state, :check_offers, without_task, @check_offers_timeout}
    end

    def wait_agreement({:go, from, new_data}, _) do
        Logger.info "go exchenge (is's agrement)!"
        GenFSM.send_event(from, :done)
        {:next_state, :check_offers, new_data,
        @check_offers_timeout}
    end

    def wait_agreement({:go_exchange, from, _task}, without_task) do
        Logger.info "I'm busy"
        GenFSM.send_event(from, {:busy, self()})
        {:next_state,
        :wait_agreement, without_task,
        @wait_agreement_timeout}
    end

    def wait_agreement({:busy, from}, without_task) do
        Logger.info "It's busy"
        Process.sleep(100 + :rand.uniform(100))
        task_data = without_task
                 |> Tasks.push_remaining_tasks([from])
        {:next_state, :check_offers,
        task_data, @check_offers_timeout}
    end

    def check_offers({:go_exchange, from, task2}, task1) do
        indexes = for i1 <- (for i <- 0..length(task1.employers)-1, do: i), i2 <-(for i <- 0..length(task2.employers)-1, do: i), do: {i1,i2}
        pairs = Enum.zip(indexes,  Enum.map(indexes,fn({i,j})->should_exchange?(task1,task2,i,j) end) )
        |>Enum.filter(fn({_,flag})->flag end)
        if length(pairs) > 0 do
            {{i1,i2},_} = pairs |> Enum.at 0
            Logger.info "Before: #{inspect task1} #{inspect task2}"
            {new_task1,new_task2} = exchange(task1,task2,i1,i2)
            Logger.info "After exchange: #{inspect new_task1} #{inspect new_task2}"
            new_new_task1 = new_task1 |> Tasks.rollback_tasks
            new_new_task2 = new_task2 |> Tasks.rollback_tasks
            Logger.info "After rollback: #{inspect new_new_task1} #{inspect new_new_task2}"
            GenFSM.send_event(from, {:go, self(), new_new_task2})
            {:next_state,
             :make_offer, {task1, new_new_task1},
             @make_offer_timeout}
         else
             Logger.info "We shouldn't exchange"
             GenFSM.send_event(from, :no)
             try_exchange(task1)
        end
        # Logger.info "check_offers"
        # if should_exchange?(task_data, other_data) do
        #     # Logger.info "We should exchange"
        #     # {new, oth_new} = Tasks.exchange(task_data, other_data)
        #     # GenFSM.send_event(from, {:go, self(), oth_new})
        #     # {:next_state,
        #     #  :make_offer, {task_data, new},
        #     #  @make_offer_timeout}
        # else
        #     Logger.info "We shouldn't exchange"
        #     GenFSM.send_event(from, :no)
        #     try_exchange(task_data)
        # end
    end

    def check_offers(:timeout, task_data), do: try_exchange(task_data)

    def check_offers(msg, task_data) do
        IO.puts "Ignored #{inspect msg}"
        {:next_state, :check_offers, task_data, @check_offers_timeout}
    end

    def make_offer(:done, {_, new}) do
        Logger.info "Exchange finished."
        try_exchange(new)
    end

    def make_offer(:timeout,  {task_data, _}) do
        try_exchange(task_data)
    end

    def make_offer({:go_exchange, from, _data}, {task_data, new}) do
        # We shouldn't update timer
        GenFSM.send_event(from, :busy)
        {:next_state,
         :make_offer, {task_data, new}
        }
    end

    def make_offer msg, {task_data, new} do
        IO.puts "Ignored #{inspect msg}"
        # We shouldn't update timer
        {:next_state,
         :make_offer, {task_data, new},
        }
    end

    def check_offers_finally({:go_exchange, from, task2}, task1) do
        Logger.info "Received offer "
        indexes = for i1 <- (for i <- 0..length(task1.employers)-1, do: i), i2 <- (for i <- 0..length(task2.employers)-1, do: i), do: {i1,i2}
        pairs = Enum.zip(indexes,  Enum.map(indexes,fn({i,j})->should_exchange?(task1,task2,i,j)end))
        |>Enum.filter(fn({_,flag})->flag end)
        if length(pairs) > 0 do
            {{i1,i2},_} = pairs|>Enum.at 0

            {new_task1,new_task2} = exchange(task1,task2,i1,i2)
            GenFSM.send_event(from, {:go, self(), new_task2})
            {:next_state,
             :make_offer_finally, {task1, new_task1},
             @make_offer_timeout}
         else
             Logger.info "We shouldn't exchange"
             GenFSM.send_event(from, :no)
             {:next_state,
              :check_offers_finally, task1,
              @check_offers_finally_timeout}
        end
        # case Tasks.try_exchange do
        #     :false ->
        #     {:true, }
        # end
        # if should_exchange?(task_data, other_data) do
            # {new, oth_new} = Tasks.exchange(task_data, other_data)
            # GenFSM.send_event(from, {:go, self(), oth_new})
            # {:next_state,
            #  :make_offer_finally,
            #  {task_data, new},
            #  @check_offers_timeout}
        # else
        #     GenFSM.send_event(from, :no)
        #     {:next_state,
        #      :check_offers_finally, task_data,
        #      @check_offers_finally_timeout}
        # end
    end

    def check_offers_finally :timeout, task_data do
        job_is_done(task_data)
    end

    def make_offer_finally :done, {_, new_data} do
        Logger.info "Exchange finished."
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
        # We shouldn't update timer
        {:next_state,
        :make_offer_finally, {old, new}}
    end

    def handle_info info, statename, state do
        IO.puts "HANDLE_INFO"
        IO.inspect(info)
        IO.inspect(statename)
        {:stop, :terminate, state}
    end

    def job_is_done task_data do
        sql   = Enum.map(task_data.employers, fn x -> x.sql      end)
             |> Enum.sum
        front = Enum.map(task_data.employers, fn x -> x.frontend end)
             |> Enum.sum
        back  = Enum.map(task_data.employers, fn x -> x.backend  end)
             |> Enum.sum
        Logger.info "I'm DONE."
                 <> "List of empls: #{inspect task_data.employers}\n"
                 <> "Skills: sql: #{inspect sql}"
                 <> "        frontend: #{inspect front}"
                 <> "        backend: #{inspect back}"
        {:stop, :normal, task_data}
    end

    # def try_exchange task1, task2 do
    #     indexes = for i1 <- (for i <-[0..length(task1.employers)], do: i), i2 <-(for i <-[0..length(task2.employers)], do: i), do: {i1,i2}
    #     pairs = Enum.zip(indexes,  Enum.map(indexes,fn({i,j})->should_exchange(task1,task2,i,j)) )
    #     |>Enum.filter(fn({_,flag})->flag)
    #     if length(pairs) > 0 do
    #         {{i1,i2},_} = pairs|>Enum.at 0
    #         {new_task1,new_task2} = exchange(task1,task2,i1,i2)
    #
    #     end
    #
    # end

    defp should_exchange? task1, task2, i1, i2 do
        local_diff = fn({a,b,c},{d,e,f}) ->
                        {abs(a-d),abs(b-e),abs(c-f)}
                    end
        #old_delta
        {od1, od2, od3} = local_diff.(Tasks.estim(task1),Tasks.estim(task2))
        {new_task1,new_task2} = exchange(task1,task2,i1,i2)
        #new_delta
        {nd1,nd2,nd3}= local_diff.(Tasks.estim(new_task1),Tasks.estim(new_task2))
        #old_delta > new_delta
        od1+od2+od3 > nd1+nd2+nd3
    end

    def exchange task1, task2, i1, i2 do
        # Logger.info "#{inspect task1}, #{inspect task2}"
        rep1 = task1.employers|>Enum.at i1
        rep2 = task2.employers|>Enum.at i2
        { %{task1 | employers: List.replace_at(task1.employers,i1,rep2)},
          %{task2 | employers: List.replace_at(task2.employers,i2,rep1)}  }
    end
end
