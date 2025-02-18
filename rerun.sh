#!/bin/bash
set -euo pipefail

# Input handling
TIMEOUT=$((${INPUT_TIMEOUT_MINUTES:-0} * 60 + ${INPUT_TIMEOUT_SECONDS:-0}))
MAX_ATTEMPTS=${INPUT_MAX_ATTEMPTS}
COMMAND=${INPUT_COMMAND}
RETRY_WAIT=${INPUT_RETRY_WAIT_SECONDS:-10}
SHELL_TYPE=${INPUT_SHELL:-bash}
RETRY_ON=${INPUT_RETRY_ON:-any}
CLEANUP_CMD=${INPUT_ON_RETRY_COMMAND:-}
NEW_CMD=${INPUT_NEW_COMMAND_ON_RETRY:-}
CONTINUE_ON_ERROR=${INPUT_CONTINUE_ON_ERROR:-false}

# Initialize counters
ATTEMPT=1
EXIT_CODE=0
FINAL_ERROR=""

function run_command() {
    local cmd
    cmd=${1:-$COMMAND}

    if [ $TIMEOUT -gt 0 ]; then
        timeout --preserve-status $TIMEOUT "$SHELL_TYPE" -c "$cmd"
    else
        $SHELL_TYPE -c "$cmd"
    fi
}

function should_retry() {
    local exit_code=$1
    local error_type=$2

    case $RETRY_ON in
    "error") [[ $exit_code -ne 0 ]] && [[ $error_type == "error" ]] ;;
    "timeout") [[ $error_type == "timeout" ]] ;;
    *) [[ $exit_code -ne 0 ]] || [[ $error_type == "timeout" ]] ;;
    esac
}

while [ $ATTEMPT -le "$MAX_ATTEMPTS" ]; do
    echo "Attempt $ATTEMPT/$MAX_ATTEMPTS:"

    # Run cleanup command between attempts
    if [ $ATTEMPT -gt 1 ] && [ -n "$CLEANUP_CMD" ]; then
        echo "Running cleanup command..."
        $SHELL_TYPE -c "$CLEANUP_CMD" || true
    fi

    # Switch command if specified
    CURRENT_CMD=$COMMAND
    if [ $ATTEMPT -gt 1 ] && [ -n "$NEW_CMD" ]; then
        CURRENT_CMD=$NEW_CMD
    fi

    set +e
    OUTPUT=$(run_command "$CURRENT_CMD" 2>&1)
    EXIT_CODE=$?
    set -e

    ERROR_TYPE="error"
    if [ $EXIT_CODE -eq 124 ]; then
        ERROR_TYPE="timeout"
        FINAL_ERROR="Timeout occurred after $TIMEOUT seconds"
    else
        FINAL_ERROR=$OUTPUT
    fi

    if should_retry $EXIT_CODE $ERROR_TYPE; then
        echo "Attempt failed (${ERROR_TYPE}), retrying in ${RETRY_WAIT}s..."
        sleep "$RETRY_WAIT"
        ATTEMPT=$((ATTEMPT + 1))
    else
        break
    fi
done

...existing code...

# Set outputs
{
    echo "total_attempts=${ATTEMPT}"
    echo "exit_code=${EXIT_CODE}"
    echo "exit_error=${FINAL_ERROR}"
} >>"$GITHUB_OUTPUT"

# Handle final exit
if [ "$CONTINUE_ON_ERROR" = "true" ]; then
    exit 0
else
    exit $EXIT_CODE
fi
