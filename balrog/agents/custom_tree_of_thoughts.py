import re
import copy

from balrog.agents.base import BaseAgent


class CustomAgent(BaseAgent):
    """An agent that generates actions and plans based on observations with a customizable approach."""

    def __init__(self, client_factory, prompt_builder, branch=3, beam=2, depth=2):
        super().__init__(client_factory, prompt_builder)
        self.client = client_factory()
        self.plan = None
        self.branch = branch   # candidates generated per node
        self.beam = beam       # nodes kept per level (BFS pruning)
        self.depth = depth     #levels of lookahead

    def _ask(self, messages):
        return self.client.generate(messages)

    def _clone_with_suffix(self, messages, suffix):
        msgs = copy.deepcopy(messages)
        if msgs and msgs[-1].role == "user":
            msgs[-1].content += "\n\n" + suffix
        return msgs


       # ---------- Step 1: generate candidates ----------
    def _generate_candidates(self, messages, path_so_far):
        history = ""
        if path_so_far:
            history = "Imagined steps so far:\n" + "\n".join(
                f"- {t['action']} ({t['thought']})" for t in path_so_far
            ) + "\n"
        suffix = (
            f"{history}"
            f"Propose {self.branch} DIFFERENT possible next moves. "
            "Use this exact format, one per line:\n"
            "1. THOUGHT: <short reasoning> | ACTION: <exact action wording>\n"
            "2. THOUGHT: ... | ACTION: ...\n"
            f"Valid actions must follow the EXACT wording from: {self.prompt_builder.system_prompt}"
        )
        resp = self._ask(self._clone_with_suffix(messages, suffix))
        return self._parse_candidates(resp.completion)

    def _parse_candidates(self, text):
        out = []
        for m in re.finditer(r"THOUGHT:\s*(.*?)\s*\|\s*ACTION:\s*(.+)", text, re.IGNORECASE):
            out.append({"thought": m.group(1).strip(), "action": m.group(2).strip().lower()})
        return out[: self.branch]

    # ---------- Step 2: evaluate ----------
    def _evaluate(self, messages, path):
        steps = "\n".join(f"- {t['action']} ({t['thought']})" for t in path)
        suffix = (
            f"Candidate sequence of moves:\n{steps}\n"
            "Rate from 1 (useless or harmful) to 10 (clearly progresses toward the goal). "
            "Consider: does it move toward the objective, avoid repeating past actions, "
            "and avoid walking into walls or obstacles? Reply with only the number."
        )
        resp = self._ask(self._clone_with_suffix(messages, suffix))
        m = re.search(r"\d+", resp.completion)
        return min(10, int(m.group())) if m else 1

    # ---------- Step 3: BFS ----------
    def _tree_search(self, messages):
        frontier = [[]]  # each entry is a path = list of thoughts
        for level in range(self.depth):
            scored = []
            for path in frontier:
                for cand in self._generate_candidates(messages, path):
                    new_path = path + [cand]
                    scored.append((self._evaluate(messages, new_path), new_path))
            if not scored:
                break
            scored.sort(key=lambda x: x[0], reverse=True)
            frontier = [p for _, p in scored[: self.beam]]   # prune to beam width
        return frontier[0] if frontier and frontier[0] else None

    def act(self, obs, prev_action=None):
        if prev_action:
            self.prompt_builder.update_action(prev_action)
        self.prompt_builder.update_observation(obs)

        messages = self.prompt_builder.get_prompt()
        best_path = self._tree_search(messages)

        if best_path:
            action = best_path[0]["action"]
            plan = " -> ".join(t["action"] for t in best_path)
        else:
            # fallback: your original single-shot prompting
            return self._fallback_act(messages)

        self.plan = plan
        response = self._ask(messages)   # need an LLMResponse object to return
        return response._replace(reasoning=plan, completion=action)
