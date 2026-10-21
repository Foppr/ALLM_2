import re
from balrog.agents.base import BaseAgent


class ReActAgent(BaseAgent):
    """An agent that uses the ReAct approach by maintaining a continuous trajectory of reasoning traces."""

    def __init__(self, client_factory, prompt_builder):
        super().__init__(client_factory, prompt_builder)
        self.client = client_factory()
        self.last_thought = None

    def act(self, obs, prev_action=None):
        """Generate the next action and thought based on the current observation and reasoning history.

        Args:
            obs (dict): The current observation in the environment.
            prev_action (str, optional): The previous action taken.

        Returns:
            LLMResponse: The response containing the reasoning trace (thought) and selected action.
        """
        if prev_action:
            # INJECT the previous thought into the action history so the LLM remembers its reasoning trace
            action_to_log = prev_action
            if self.last_thought and self.last_thought != "No reasoning provided.":
                action_to_log = f"THOUGHT: {self.last_thought}\nACTION: {prev_action}"

            self.prompt_builder.update_action(action_to_log)

        self.prompt_builder.update_observation(obs)

        # ReAct instructions requiring both a thought and an action
        react_instructions = """
Self-Reflection & Reasoning Phase:
Before deciding on your next action, think step-by-step about the current situation. 
Analyze the current observation, reflect on your past thoughts and actions, and deduce your next logical step.
You must output a thought and an action at every step.

Format your answer EXACTLY in the following way:
THOUGHT: <your step-by-step reasoning and reflection on the current state>
ACTION: <your next action>
        """.strip()

        messages = self.prompt_builder.get_prompt()
        if messages and messages[-1].role == "user":
            messages[-1].content += "\n\n" + react_instructions

        response = self.client.generate(messages)

        # Extract the thought and action from the LLM's response
        thought, action = self._extract_thought_and_action(response.completion)

        # Save the thought internally to append to the history in the next step
        self.last_thought = thought

        # Save the thought in the response.reasoning field and the action in response.completion
        response = response._replace(reasoning=thought, completion=action)
        return response

    def _extract_thought_and_action(self, response_text):
        """Extract the thought and action from the LLM's ReAct response text.

        Args:
            response_text (str): The response text from the LLM.

        Returns:
            tuple: A tuple containing the extracted thought and action.
        """
        # Parse the THOUGHT and ACTION blocks using regex
        thought_match = re.search(r"THOUGHT:\s*(.*?)(?=\nACTION:|\Z)", response_text, re.IGNORECASE | re.DOTALL)
        action_match = re.search(r"ACTION:\s*(.*)", response_text, re.IGNORECASE | re.DOTALL)

        thought = thought_match.group(1).strip() if thought_match else "No reasoning provided."
        action = action_match.group(1).strip() if action_match else None

        return thought, action