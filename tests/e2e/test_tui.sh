#!/bin/bash

# set -e

SESSION="pi_test"

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

echo "Waiting for extension to be loaded..."
# Use a loop to wait for the "Hello extension loaded!" message
MAX_RETRIES=30
COUNT=0
while ! tmux capture-pane -t $SESSION -p | grep -q "Hello extension loaded!"; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Timeout: Extension message not found!"
        echo "--------------------------------------------------"
        echo "Pane content at timeout:"
        tmux capture-pane -t $SESSION -p
        echo "--------------------------------------------------"
        exit 1
    fi
    sleep 0.5
    ((COUNT++))
done
echo "Extension detected!"

echo "Sending /menu command..."
tmux send-keys -t $SESSION "/menu" Enter
sleep 1

echo "Waiting for menu..."
# Wait for the menu to appear
COUNT=0
while ! tmux capture-pane -t $SESSION -p | grep -q "Choose an option:"; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Timeout: Menu not found!"
        exit 1
    fi
    sleep 0.5
    ((COUNT++))
done

echo "Sending Down Arrow..."
tmux send-keys -t $SESSION Down
sleep 1

echo "Sending Enter..."
tmux send-keys -t $SESSION Enter

echo "Waiting for result..."
# Wait for the result
COUNT=0
while ! tmux capture-pane -t $SESSION -p | grep -q "You chose: Option B"; do
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Timeout: Result not found!"
        echo "--------------------------------------------------"
        echo "Pane content at timeout:"
        tmux capture-pane -t $SESSION -p
        echo "--------------------------------------------------"
        exit 1
    fi
    sleep 0.5
    ((COUNT++))
done

echo "--------------------------------------------------"
echo "✅ E2E TEST PASSED: Menu navigation and selection worked!"
echo "--------------------------------------------------"

exit 0
