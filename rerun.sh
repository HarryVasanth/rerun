#!/bin/bash
set -euo pipefail

# Input handling
TIMEOUT=$((${INPUT_TIMEOUT_MINUTES:-0} * 60 + ${INPUT_TIMEOUT_SECONDS:-0}))
MAX_ATTEMPTS=${INPUT_MAX_ATTEMPTS:-1}
COMMAND=${INPUT_COMMAND:-}
RETRY_WAIT=${INPUT_RETRY_WAIT_SECONDS:-10}
EXPONENTIAL_BACKOFF=${INPUT_EXPONENTIAL_BACKOFF:-false}
SHELL_TYPE=${INPUT_SHELL:-bash}
RETRY_ON=${INPUT_RETRY_ON:-any}
CLEANUP_CMD=${INPUT_ON_RETRY_COMMAND:-}
NEW_CMD=${INPUT_NEW_COMMAND_ON_RETRY:-}
CONTINUE_ON_ERROR=${INPUT_CONTINUE_ON_ERROR:-false}

# Initialize counters
ATTEMPT=1
EXIT_CODE=0
FINAL_ERROR=""

run_command() {
	local cmd
	cmd=${1:-$COMMAND}

	if [ "$TIMEOUT" -gt 0 ]; then
		timeout "$TIMEOUT" "$SHELL_TYPE" -c "$cmd"
	else
		"$SHELL_TYPE" -c "$cmd"
	fi
}

should_retry() {
	local exit_code=$1
	local error_type=$2

	case $RETRY_ON in
	"error") [[ "$exit_code" -ne 0 ]] && [[ "$error_type" == "error" ]] ;;
	"timeout") [[ "$error_type" == "timeout" ]] ;;
	*) [[ "$exit_code" -ne 0 ]] || [[ "$error_type" == "timeout" ]] ;;
	esac
}

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
	echo "🔄 Attempt $ATTEMPT/$MAX_ATTEMPTS:"

	# 🧹 Run cleanup command between attempts
	if [ "$ATTEMPT" -gt 1 ] && [ -n "$CLEANUP_CMD" ]; then
		echo "🧹 Running cleanup command..."
		"$SHELL_TYPE" -c "$CLEANUP_CMD" || true
	fi

	# Switch command if specified for retries
	CURRENT_CMD=$COMMAND
	if [ "$ATTEMPT" -gt 1 ] && [ -n "$NEW_CMD" ]; then
		CURRENT_CMD=$NEW_CMD
	fi

	set +e
	OUTPUT=$(run_command "$CURRENT_CMD" 2>&1)
	EXIT_CODE=$?
	set -e

	# Evaluate exit code
	if [ "$EXIT_CODE" -eq 0 ]; then
		ERROR_TYPE="none"
		FINAL_ERROR=""
		echo "✅ Success! (Exit Code: 0)"
	elif [ "$EXIT_CODE" -eq 124 ]; then
		ERROR_TYPE="timeout"
		FINAL_ERROR="Timeout occurred after $TIMEOUT seconds"
		echo "⏱️ $FINAL_ERROR"
	else
		ERROR_TYPE="error"
		FINAL_ERROR=$OUTPUT
		echo "❌ Execution failed with exit code $EXIT_CODE."
	fi

	# Decide next steps
	if should_retry "$EXIT_CODE" "$ERROR_TYPE"; then
		if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
			echo "🛑 Attempt failed (${ERROR_TYPE}). Maximum attempts ($MAX_ATTEMPTS) reached."
			break
		fi

		# Calculate wait time
		CURRENT_WAIT=$RETRY_WAIT
		if [ "$EXPONENTIAL_BACKOFF" = "true" ]; then
			MULTIPLIER=$((2 ** (ATTEMPT - 1)))
			CURRENT_WAIT=$((RETRY_WAIT * MULTIPLIER))
		fi

		echo "⏳ Attempt failed (${ERROR_TYPE}), retrying in ${CURRENT_WAIT}s..."
		sleep "$CURRENT_WAIT"
		ATTEMPT=$((ATTEMPT + 1))
	else
		break
	fi
done

# Output multiline errors for GH Actions
EOF_MARKER="EOF_$(date +%s)_$RANDOM"

{
	echo "total_attempts=${ATTEMPT}"
	echo "exit_code=${EXIT_CODE}"
	echo "exit_error<<${EOF_MARKER}"
	echo "${FINAL_ERROR}"
	echo "${EOF_MARKER}"
} >>"$GITHUB_OUTPUT"

# Handle final exit
if [ "$CONTINUE_ON_ERROR" = "true" ]; then
	echo "⏭️ continue_on_error is true. Forcing exit code 0."
	exit 0
else
	exit "$EXIT_CODE"
fi
