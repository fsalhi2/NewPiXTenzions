#!/bin/bash

SESSION="pi_test_system_prompt"

# Cleanup function
cleanup() {
    echo "Cleaning up tmux session..."
    tmux kill-session -t $SESSION 2>/dev/null
}
trap cleanup EXIT

echo "Starting tmux session with pi..."
# Start a new session and run pi
tmux new-session -d -s $SESSION "pi"
tmux set-option -t $SESSION extended-keys on

echo "Waiting for pi to be ready..."
# We wait for the prompt or a recognizable starting string.
# Since we don't know the exact starting string, let's wait for a bit or look for common patterns.
MAX_RETRIES=30
COUNT=0
# Let's assume the agent displays something like "Welcome" or just shows the prompt.
# For now, we'll wait for the presence of the command line or just a timeout.
while ! tmux capture-pane -t $SESSION -p | grep -qE "([a-zA-Z0-9_]+@|pi|$)"; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Timeout: Pi didn't seem to start!"
        exit 1
    fi
    sleep 1
    ((COUNT++))
done
echo "Pi is ready!"

echo "Sending 'Hello' to trigger the system prompt check..."
tmux send-keys -t $SESSION "Hello" Enter
sleep 2

echo "Checking for 'ROBOT_ACTIVE' in the output..."
# We might need to wait a bit for the LLM to respond
MAX_RETRIES=20
COUNT=0
FOUND=false
while [ $COUNT -lt $MAX_RETRIES ]; do
    if tmux capture-pane -t $SESSION -p | grep -q "ROBOT_ACTIVE"; then
        FOUND=true
        break
    fi
    sleep 1
    ((COUNT++))
done

if [ "$FOUND" = true ]; then
    echo "--------------------------------------------------"
    echo "✅ E2E TEST PASSED: System prompt update detected!"
    echo "--------------------------------------------------"
    exit 0
else
    echo "--------------------------------------------------"
    echo "❌ E2E TEST FAILED: 'ROBOT_ACTIVE' not found in output!"
    echo "--------------------------------------------------"
    echo "Current pane content:"
    tmux capture-pane -t $SESSION -p
    exit 1
fi
