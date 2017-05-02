defmodule TaskSpec do
    @doc """
    employers: employers in current task
    remaining_tasks: - pid-s of tasks-agents (include self() !!!)
    """
    defstruct employers: [],
              all_tasks: [],
              remaining_tasks: []
end

defprotocol TaskProto do
    @doc """
    We are trying to find employer in our task
    To replace it with `empl`
    Returns: (True, updatet it) if found
             False              otherwise
    """
    def try_exchange(it, empl)
    def push_employers(it, empls)
    def push_remaining_tasks(it, tasks)
    def pop_remaining_task(it)
    def rollback_tasks(it)
    def estim(it)
end

defimpl TaskProto, for: TaskSpec do
    def try_exchange(_it, _empl) do
        # Some magic
        :false
    end
    def rollback_tasks(it) do
        %{it | remaining_task: it.all_tasks}
    end
    def push_employers(it, empl) do
        %{it | employers: [empl] + [it.employers]}
    end
    def push_remaining_tasks(it, tasks) do
        %{it | remaining_tasks: it.remaining_tasks ++ tasks}
    end
    def pop_remaining_task(it) do
        case it.remaining_tasks do
            [] -> nil
            [t|tasks] ->
                {t, %{it | remaining_tasks: tasks}}
        end
    end

    def estim(it) do
        Enum.map(it.employers, fn(x)->x.sql + x.frontend + x.backend end) |> Enum.sum
    end

end
