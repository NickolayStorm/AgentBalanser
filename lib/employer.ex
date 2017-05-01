defmodule EmployerData do
    defstruct sql: 0,
              frontend: 0,
              backend: 0
end

defmodule Employer do
    use GenFSM
    require Logger

    @wait_invitation_timeout 5_000
    @wait_command_agreement_timeout 1_000

    def start_link data do
        {:ok, pid} = GenFSM.start_link(__MODULE__, data, [{:debug, [:log, :trace]}])
        pid
    end

    def init(data) do
        # Будем хранить не только данные, но и список инвайтов
        {:ok, :wait_invitation, {data, []}}
    end

    def wait_invitation(:timeout, {data, invitations}) do
        Logger.info "Перестали ждать работников"
        # If not empty
        Logger.info "#{inspect invitations}"
        sorted = sort_by_skill(invitations)
        Logger.info "Sorted"
        [pid | other] = sorted
        Logger.info "разложено"
        Gen_FSM.send_event(pid, {:go, data, self()})
        Logger.info "Sent"
        {
            :next_state, :wait_command_agreement,
            {data, other},
            @wait_command_agreement_timeout
        }
    end

    def wait_invitation({:invite, from}, {data, invitations}) do
        Logger.info "Employer #{inspect self()}"
                 <> "received invite from #{inspect from}"
        {
            :next_state, :wait_invitation,
            {data, [from | invitations]},
            @wait_invitation_timeout
        }
    end

    def sort_by_skill invitations do
        pairs = invitations
             |> Enum.map(
                fn pid ->
                     empls = pid |> GenFSM.sync_send_all_state_event(:send_me_list)
                     Logger.info "Empls in curr pid #{empls}"
                     case empls do
                         [] -> {pid, 0}
                         lst ->
                             {
                                 pid,
                                 Enum.sum(Enum.map(lst, fn e -> e.sql      end)) +
                                 Enum.sum(Enum.map(lst, fn e -> e.frontend end)) +
                                 Enum.sum(Enum.map(lst, fn e -> e.backend  end))
                             }
                     end
                 end
             )
         Logger.info("After")
         sorted_pairs = pairs |> Enum.sort_by(
                         fn {_, sum} -> sum end
                     )
         Logger.info("After2")
         sorted = sorted_pairs |> Enum.map(fn {pid, _} -> pid end)
         Logger.info("Result: #{sorted}")
         sorted
    end

    def wait_command_agreement({:ok, from}, data) do
        Logger.info "Employer #{inspect self()} "
                 <> "was connected to command #{inspect from}"
        {:stop, :normal, data}
    end

    def wait_command_agreement({:no, from}, {data, invitations}) do
        Logger.info "Employer #{inspect self()} "
                 <> "received renouncement from command #{inspect from}"
        [pid | other] = sort_by_skill(invitations)
        Gen_FSM.send_event(pid, {:go, data, self()})
        {
            :next_state, :wait_command_agreement,
            {data, other},
            @wait_command_agreement_timeout
        }
    end

    def wait_command_agreement(:timeout, {data, invitations}) do
        Logger.info "Employer #{inspect self()} "
                 <> "on timeout"
        case invitations do
            [] -> Logger.info "Empty command list; what's going on? "
                           <> "Terminated."
                  {
                      :stop, {:shutdown, :error}, nil
                  }
            [pid | other] -> sort_by_skill(invitations)
                Gen_FSM.send_event(pid, {:go, data, self()})
                {
                    :next_state, :wait_command_agreement,
                    {data, other},
                    @wait_command_agreement_timeout
                }
        end
    end
    def wait_command_agreement(:invite, data) do
        {
            :next_state, :wait_command_agreement,
            data,
            @wait_command_agreement_timeout
        }
    end
end
