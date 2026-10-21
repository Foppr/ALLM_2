import re
from collections import Counter

from balrog.agents.base import BaseAgent


class CustomAgent(BaseAgent):
    """An agent that generates actions and plans based on observations with a customizable approach."""

    def __init__(self, client_factory, prompt_builder):
        super().__init__(client_factory, prompt_builder)
        self.client = client_factory()
        self.plan = None
        self.obs_history = []
        self.act_history = []

    def act(self, obs, prev_action=None):
        """Generate the next action and update the plan based on the current observation.

        Args:
            obs (dict): The current observation in the environment.
            prev_action (str, optional): The previous action taken.

        Returns:
            LLMResponse: The response containing the updated plan and selected action.
        """
        if prev_action:
            self.prompt_builder.update_action(prev_action)
        self.prompt_builder.update_observation(obs)

        planning_instructions = f"""Solve the puzzle by making a plan, carefully considering the observation, what your surroundings look like and where you might want to go to achieve the goal.
        Always start your response with "Let's think step by step". After your reasoning steps, end the response with "ACTION: <your action>". 
        It is VERY important to follow the exact phrasing of the action as given in the task description, otherwise it is invalid.
        """.strip()

        # ADD: Detect if the agent is going in circles
        obs_text = obs["text"]["long_term_context"]
        warning = ""
        if obs_text in self.obs_history[-4:]:
            warning = ("\n\nWARNING: you saw this exact observation a few steps ago. "
                       f"Your last actions were: {', '.join(self.act_history[-4:])}. "
                       "You are going in circles. Turning back and forth does not explore anything new.\n")
        self.obs_history.append(obs_text)

        messages = self.prompt_builder.get_prompt()
        if messages and messages[-1].role == "user":
            messages[-1].content += "\n\n" + planning_instructions + warning

        # append `warning` to messages[-1].content; after choosing, self.act_history.append(final_action)

        self.last_prompt = "\n\n".join(f"[{m.role}]\n{m.content}" for m in messages)  # ADD prompt to agent

        # ADD: Self-consistency - several reasoning paths, then a majority vote
        samples = []  # (response, action) per sample
        for i in range(5):
            r = self.client.generate(messages)
            samples.append((r, self._extract_action(r.completion)))

        valid = [a for _, a in samples if a]  # ignore samples without a valid action
        if valid:
            final_action, votes = Counter(valid).most_common(1)[0]
        else:
            final_action, votes = None, 0  # evaluator falls back to its default action

        # ADD: keep track of action_history
        self.act_history.append(final_action)

        # use the reasoning of one sample that voted for the winner
        winner = next((r for r, a in samples if a == final_action), samples[0][0])

        self.raw_response = "\n\n".join(f"Response {i + 1} -> {a}:\n{r.completion}" for i, (r, a) in enumerate(samples))
        self.prompt_builder.update_reasoning(winner.completion or "")  # only the winning reasoning goes into history

        return winner._replace(
            completion=final_action,
            reasoning=f"votes: {dict(Counter(a for _, a in samples))}\n\n{winner.completion}",
            input_tokens=sum(r.input_tokens or 0 for r, _ in samples),
            output_tokens=sum(r.output_tokens or 0 for r, _ in samples),
        )

    def _extract_action(self, response_text):
        """Extract the plan and action from the LLM's response text.

        Args:
            response_text (str): The response text from the LLM.

        Returns:
            tuple: A tuple containing the extracted plan and action.
        """
        action_match = re.search(r"ACTION:\s*(.*)", response_text, re.IGNORECASE | re.DOTALL)

        # CHANGE: do not penalize LLM for capitalizing action or adding punctuation
        action = action_match.group(1).strip() if action_match else None
        if action:
            action = action.splitlines()[0]  # only the first line
            action = action.strip().strip(".!\"'`*").lower()  # drop trailing period, quotes, markdown **

        return action
