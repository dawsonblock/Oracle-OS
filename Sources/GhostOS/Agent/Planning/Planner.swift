public struct Planner {

    public func plan(goal: String) -> Plan {

        if goal.contains("send email") {

            return Plan(
                goal: goal,
                steps: [
                    "focus_browser",
                    "open_gmail",
                    "compose_email",
                    "send_email"
                ]
            )
        }

        return Plan(goal: goal, steps: [])
    }
}
