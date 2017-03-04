defmodule TaskSpec do
    @doc """
    task: needed skill count for current task
    skill_sum: is Enum.sum employers
    remaining_tasks: - pid-s of tasks-agents (include self() !!!)
    employers: list should be sorted.
               It's reversed when skill_sum > task
    """
    defstruct task: 0,
              employers: [],
              all_tasks: [],
              remaining_tasks: [],
              skill_sum: 0
end

defprotocol TaskProto do
    @doc "set task; return new struct"
    def set_its_task(it, task)
    @doc "push employer; return new struct"
    def push_employer(it, empl)
    @doc "pop employer; return {empl, struct}"
    def pop_employer(it)
    @doc "push list of other tasks; return new struct"
    def push_remaining_tasks(it, tasks)
    @doc "pop other task; return ({empl, struct} | nil)"
    def pop_remaining_task(it)
    @doc "return abs(task-skill_sum)"
    def disbalance(it)
    @doc "true if skill_sum == task"
    def is_balanced(it)
    @doc "Change first employees; return {its_updated, other_updated}"
    def exchange(it, other)
end

defimpl TaskProto, for: TaskSpec do

    def disbalance(it) do
        abs(it.task - it.skill_sum)
    end

    def set_its_task(it, task) do
        %{it | task: task}
    end

    def push_employer(it, empl) do
        is_more_aftr_push = it.skill_sum + empl > it.task
        empls = if is_more_aftr_push do
                    [empl | it.employers]
                    |> Enum.sort
                    |> Enum.reverse
                else
                    [empl | it.employers]
                    |> Enum.sort
                end

        %{it | employers: empls,
               skill_sum: it.skill_sum + empl}
    end

    def pop_employer(it) do
        [e|empls] = it.employers
        {
            e,
            %{it | employers: empls,
                   skill_sum: it.skill_sum - e}
        }
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

    def is_balanced it do
        it.task == it.skill_sum
    end

    def exchange data, other do
        {m_e, m_updated} = data  |> pop_employer
        {o_e, o_updated} = other |> pop_employer
        m_new = m_updated |> push_employer(o_e)
        o_new = o_updated |> push_employer(m_e)
        {m_new, o_new}
    end
end
