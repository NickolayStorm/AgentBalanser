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
        sorted = sort_by_skill(invitations)
        [pid | other] = sorted
        GenFSM.send_event(pid, {:go, data, self()})
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
        # Logger.info "Sort by skill"
        pairs = invitations
             |> Enum.map(
                fn pid ->
                    #  Logger.info "Allo"
                     empls = pid |> GenFSM.sync_send_all_state_event(:send_me_list, 10_000)
                     case empls do
                         [] -> {pid, 0}
                         lst ->
                             sql = Enum.sum(Enum.map(lst, fn e -> e.sql      end))
                             front = Enum.sum(Enum.map(lst, fn e -> e.frontend end))
                             {
                                 pid,
                                 front + sql +
                                 Enum.sum(Enum.map(lst, fn e -> e.backend  end)) / length(lst)
                             }
                     end
                 end
             )
         sorted_pairs = pairs |> Enum.sort_by(
                         fn {_, sum} -> sum end
                     )
         sorted = sorted_pairs |> Enum.map(fn {pid, _} -> pid end)
         sorted
    end

    def wait_command_agreement({:ok, from}, data) do
        Logger.info "Employer #{inspect self()} "
                 <> "was connected to command #{inspect from}"
                 <> "\nStop process."
        {:stop, :normal, data}
    end

    def wait_command_agreement({:no, from}, {data, invitations}) do
        Logger.info "Employer #{inspect self()} "
                 <> "received renouncement from command #{inspect from}"
        [pid | other] = sort_by_skill(invitations)
        GenFSM.send_event(pid, {:go, data, self()})
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
                GenFSM.send_event(pid, {:go, data, self()})
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
