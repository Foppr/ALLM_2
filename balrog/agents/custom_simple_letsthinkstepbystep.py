import re

from balrog.agents.base import BaseAgent


class CustomAgent(BaseAgent):
    """An agent that generates actions and plans based on observations with a customizable approach."""

    def __init__(self, client_factory, prompt_builder):
        super().__init__(client_factory, prompt_builder)
        self.client = client_factory()
        self.plan = None

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

        messages = self.prompt_builder.get_prompt()
        if messages and messages[-1].role == "user":
            messages[-1].content += "\n\n" + planning_instructions

        self.last_prompt = "\n\n".join(f"[{m.role}]\n{m.content}" for m in messages)  # ADD prompt to agent

        response = self.client.generate(messages)
        self.raw_response = response
        self.prompt_builder.update_reasoning(response.completion or "")  # <-- store the full answer

        # Extract the plan and action from the LLM's response
        action = self._extract_action(response.completion)

        # Save the plan in the response.reasoning field and the action in response.completion
        response = response._replace(reasoning=response.completion, completion=action)
        return response

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
