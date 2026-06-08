# Prompt Evaluation Suite with Promptfoo

This directory documents the prompt evaluation setup for the Dutch card game agents. We use **Promptfoo** to test, validate, and protect our LLM prompts against regressions, hallucinations, formatting errors, and rule-coaching drift.

---

## 1. Overview & Goals

The project employs two distinct AI agents:
1. **Chippy (Rules Coach)**: A read-only helper that answers player questions about gameplay rules, abilities, and table scenery.
2. **Dutch Player Agent (Bot)**: An autonomous FSM-driven card-playing bot that interacts with the authoritative game state via tool calls.

To ensure both agents perform reliably under code changes, we test them across two environments:
* **Offline Mock Mode**: A fast, deterministic dry-run utilizing static mock outputs. Perfect for CI/CD integration and verifying promptfoo assertions.
* **Live LM Studio Mode**: Queries the actual loaded local LLM (`qwen/qwen3.5-9b`) to test reasoning accuracy, instruction compliance, and structural JSON tool-calling formatting.

---

## 2. Directory Structure

All evaluation resources are located inside the `evals/` folder:

```text
evals/
├── chippy.yaml                # Chippy rules coach test suite configuration
├── bot.yaml                   # Bot action decision-making test suite configuration
├── mock_provider.py           # Custom Python script returning deterministic mock answers
├── run_evals.sh               # Execution script managing paths, environments, and filters
└── prompts/
    ├── chippy_prompt.json     # Structured chat prompt template for Chippy
    └── bot_prompt.json        # Structured chat prompt template for the Bot
```

---

## 3. Prompt Formatting & Game Context

Both Chippy and the Bot require specific context values to make correct decisions (e.g. allowed actions, grounded rule drafts, FSM states). We isolated their prompts inside JSON chat templates to structure the API payloads identically to the production Godot game:

* **Chippy Chat Prompt (`chippy_prompt.json`)**:
  Formulates a `system` instruction detailing Chippy's behavior, and a `user` prompt structure that compiles grounded rules and state properties:
  ```json
  [
    { "role": "system", "content": "You are Chippy..." },
    { "role": "user", "content": "Game context: {{context}}\nGrounded draft: {{grounded_draft}}\nQuestion: {{question}}" }
  ]
  ```
* **Bot Chat Prompt (`bot_prompt.json`)**:
  Formulates the autonomous bot guidelines as a `system` instruction, and structures the `user` input as the serialized decision context dictionary:
  ```json
  [
    { "role": "system", "content": "You are Dutch Player Agent..." },
    { "role": "user", "content": "{{context}}" }
  ]
  ```

---

## 4. CPU Reasoning & Latency Optimizations

Because local models (like `qwen/qwen3.5-9b`) utilize internal reasoning steps (generating a `<think>` block before answering) and may run on CPU, we implemented three crucial optimizations:

1. **Extended Timeouts**: Set `timeoutMs: 300000` (5 minutes) at the top of our YAML configurations and exported `REQUEST_TIMEOUT_MS=300000` in our runner shell script to prevent Promptfoo from aborting requests while the model is thinking.
2. **Expanded Token Budgets**: Increased `max_tokens` to `1500` per call to ensure Qwen's thinking process does not get cut off mid-thought, allowing it to output the actual answer.
3. **Grounded Test Variables**: Injected authentic rule text directly inside each Chippy test case as the `grounded_draft` variable. By passing the exact RAG rules to the model, we eliminate confusion and infinite reasoning loops.

---

## 5. Test Cases & Assertions

We maintain a suite of **20 test cases** checking specific game logic:

### Chippy (13 Test Cases)
* **Jump-In Rule**: Assures the coach explains matching card rules (`assert: contains-any: ['match', 'discard']`).
* **Abilities**: Validates explanation of Queens, Kings of Diamonds, and purchasing cards from the chicken.
* **FSM Actions**: Verifies Chippy permits or blocks drawing, ending turns, or calling Dutch based on the active state.
* **Scenery**: Ensures Chippy explains tavern elements as bar atmosphere.

### Dutch Player Bot (7 Test Cases)
* **Start Draw**: Assures the model selects `draw_card` tool under state `TURN_START_DRAW`.
* **Resolve Drawn**: Assures the model selects `discard_drawn_card` or `swap_drawn_card` under `TURN_RESOLVE_DRAWN`.
* **Abilities**: Validates tool triggers for `complete_queen_peek`, `complete_jack_swap`, `buy_ability`, and `use_ability`.
* **Dutch Call**: Validates FSM tool choice under `TURN_CONFIRM_DUTCH`.

---

## 6. How to Run the Evaluations

### Pre-requisites
Make sure Node.js is installed. If running live evaluations, start LM Studio, load your model (`qwen/qwen3.5-9b`), and ensure the local port is active (`http://127.0.0.1:1234`).

### Run Offline / Mock Mode (CI/CD)
Fast, zero-latency validation of assertions and yaml formats:
```bash
./evals/run_evals.sh --mock
```

### Run Live LLM Mode (Full Suite)
Runs all 20 test cases against the live LM Studio API:
```bash
./evals/run_evals.sh
```

### Run Live LLM Mode (Filter / Smoke Test)
To run a sample of tests (e.g. 1 test case per agent) to verify live routing quickly:
```bash
./evals/run_evals.sh -n 1
```
