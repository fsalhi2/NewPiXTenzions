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
