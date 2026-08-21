## Testing

We implement real End-to-End (E2E) tests that interact with the actual TUI using `tmux` and `expect` to ensure high fidelity without mocking.

### What these tests validate

The E2E tests verify the entire "Stack" of the extension lifecycle:
1.  **Extension Loading**: Ensures `pi` correctly discovers, loads, and executes the entry point.
2.  **TUI Rendering**: Verifies that interactive components (like menus, selects, or custom widgets) are correctly rendered in the terminal buffer.
3.  **Terminal Interaction**: Validates that the engine correctly interprets low-level keyboard sequences (Arrow keys, Enter, etc.) sent via a pseudo-terminal (PTY).
4.  **Feedback Loop**: Confirms that the user's input triggers the expected logic and that the resulting visual feedback is displayed to the user.

### Running E2E tests

```bash
docker run --rm \
  -v $(pwd)/src:/app \
  -v $(pwd)/tests:/tests \
  -e PI_AUTH_RUNPOD="your_key" \
  pi-runtime timeout 15s bash /tests/e2e/test_tui.sh
```

## Agent Autonomy & Auto-Evolution Workflow

The project is designed to enable the agent to autonomously develop, test, and evolve its own codebase. This is achieved through a decoupled architecture between the **Workspace** and the **Runtime Container**.

### Decoupled Architecture

*   **Workspace (`/app`)**: The live development environment. It contains the source code, extensions, prompts, and tests. The agent interacts directly with this directory to make changes.
*   **Runtime Container (Ephemeral)**: An immutable execution environment. At startup, the container performs a **physical copy** (not a symlink) of the workspace components (prompts, tools, extensions) into the agent's internal configuration directory (`/root/.pi/agent`).

### The Auto-Evolution Cycle

This "Copy-based" approach allows for a safe, Test-Driven Development (TDD) cycle performed entirely by the agent:

1.  **Modification**: The agent modifies its own source code, prompts, or extensions within the **Workspace**.
2.  **Isolation**: Because the running agent uses a local copy of the configuration, its current execution remains stable and unaffected by the ongoing changes in the workspace.
3.  **Validation (The "Snapshot" Test)**: To verify the evolution, the agent spawns a **new, ephemeral container** pointing to the current workspace (or a specific new branch). This new container performs a fresh copy of the modified files.
4.  **Testing**: The agent runs E2E tests within this new container to ensure the changes are functional and do not break the TUI or core logic.
5.  **Commit & Deployment**: Upon successful validation, the agent uses its Git PAT to commit the changes, create a new branch, and push it to the remote repository, effectively creating a new official revision.

This mechanism ensures that every evolution is fully tested in a clean, isolated environment before being integrated.
