#!/bin/bash
# Rerun a command with a timeout and retries.
#
# This is a composite action script. It needs bash and standard system tools.
# It does not use Docker or Node. See action.yml for the inputs.

set -euo pipefail

# --- 🧾 Output helpers -------------------------------------------------------

error() { echo "::error::❌ $*" >&2; exit 1; }
warn() { echo "::warning::⚠️ $*"; }
notice() { echo "::notice::✅ $*"; }
debug() { [ "${RUNNER_DEBUG:-}" = "1" ] && echo "::debug::$*" || true; }

# Write one output. Print it when the script runs outside GitHub Actions.
write_output() {
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
	else
		printf '%s=%s\n' "$1" "$2"
	fi
}

# Write one multiline output. Use a random delimiter to keep the value intact.
write_multiline_output() {
	local delimiter
	delimiter="EOF_$(date +%s)_$RANDOM"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		{
			printf '%s<<%s\n' "$1" "$delimiter"
			printf '%s\n' "$2"
			printf '%s\n' "$delimiter"
		} >>"$GITHUB_OUTPUT"
	else
		printf '%s=%s\n' "$1" "$2"
	fi
}

# --- 🔢 Input helpers -------------------------------------------------------

is_uint() { case ${1:-} in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

lower() {
	local v
	v=$(trim "${1:-}")
	printf '%s' "$v" | tr '[:upper:]' '[:lower:]'
}

# Strip the CR that Windows shells can leave in env values.
trim() { local v=${1:-}; v=${v%$'\r'}; printf '%s' "$v"; }

# Read a whole number. Set $NUM. Stop on a bad value.
num() {
	local raw=${2:-} min=${4:-0}
	if [ -z "$raw" ]; then
		raw=$3
	fi
	raw=$(trim "$raw")
	is_uint "$raw" || error "$1 must be a non-negative integer"
	NUM=$((10#$raw))
	if [ "$NUM" -lt "$min" ]; then
		error "$1 must be at least $min"
	fi
}

# --- 📥 Inputs --------------------------------------------------------------

num timeout_minutes "${INPUT_TIMEOUT_MINUTES:-}" 0 0
TIMEOUT_MINUTES=$NUM
num timeout_seconds "${INPUT_TIMEOUT_SECONDS:-}" 0 0
TIMEOUT_SECONDS=$NUM
TIMEOUT=$((TIMEOUT_MINUTES * 60 + TIMEOUT_SECONDS))

num max_attempts "${INPUT_MAX_ATTEMPTS:-}" 3 1
MAX_ATTEMPTS=$NUM
num retry_wait_seconds "${INPUT_RETRY_WAIT_SECONDS:-}" 10 0
RETRY_WAIT=$NUM
num polling_interval_seconds "${INPUT_POLLING_INTERVAL_SECONDS:-}" 1 1
POLL=$NUM
num max_retry_wait_seconds "${INPUT_MAX_RETRY_WAIT_SECONDS:-}" 300 1
MAX_RETRY_WAIT=$NUM

COMMAND=$(trim "${INPUT_COMMAND:-}")
if [ -z "$COMMAND" ]; then
	error "command is required"
fi

ON_RETRY_COMMAND=$(trim "${INPUT_ON_RETRY_COMMAND:-}")
NEW_COMMAND_ON_RETRY=$(trim "${INPUT_NEW_COMMAND_ON_RETRY:-}")

RETRY_ON=$(lower "${INPUT_RETRY_ON:-any}")
case $RETRY_ON in
any | error | timeout) ;;
*) error "retry_on must be any, error or timeout" ;;
esac

RETRY_ON_EXIT_CODE=${INPUT_RETRY_ON_EXIT_CODE:-}
if [ -n "$RETRY_ON_EXIT_CODE" ]; then
	num retry_on_exit_code "$RETRY_ON_EXIT_CODE" 0 0
	RETRY_ON_EXIT_CODE=$NUM
	if [ "$RETRY_ON_EXIT_CODE" -gt 255 ]; then
		error "retry_on_exit_code must be between 0 and 255"
	fi
fi

EXPONENTIAL_BACKOFF=$(lower "${INPUT_EXPONENTIAL_BACKOFF:-false}")
case $EXPONENTIAL_BACKOFF in
true | false) ;;
*) error "exponential_backoff must be true or false" ;;
esac

WARNING_ON_RETRY=$(lower "${INPUT_WARNING_ON_RETRY:-true}")
case $WARNING_ON_RETRY in
true | false) ;;
*) error "warning_on_retry must be true or false" ;;
esac

CONTINUE_ON_ERROR=$(lower "${INPUT_CONTINUE_ON_ERROR:-false}")
case $CONTINUE_ON_ERROR in
true | false) ;;
*) error "continue_on_error must be true or false" ;;
esac

# --- 🐚 Shell ---------------------------------------------------------------

HOST_OS=${RUNNER_OS:-$(uname -s)}
case $HOST_OS in
MINGW* | MSYS* | CYGWIN* | [Ww]indows*) HOST_OS=Windows ;;
esac

SHELL_TYPE=$(lower "${INPUT_SHELL:-bash}")
case $SHELL_TYPE in
bash)
	INTERPRETER="bash"
	SHELL_ARGS=(-c)
	;;
sh)
	if [ "$HOST_OS" = Windows ]; then
		error "shell sh is not supported on Windows"
	fi
	INTERPRETER="sh"
	SHELL_ARGS=(-c)
	;;
python)
	if command -v python3 >/dev/null 2>&1; then
		INTERPRETER="python3"
	else
		INTERPRETER="python"
	fi
	SHELL_ARGS=(-c)
	;;
pwsh)
	INTERPRETER="pwsh"
	SHELL_ARGS=(-Command)
	;;
powershell)
	if [ "$HOST_OS" != Windows ]; then
		error "shell powershell is only supported on Windows"
	fi
	INTERPRETER="powershell"
	SHELL_ARGS=(-Command)
	;;
cmd)
	if [ "$HOST_OS" != Windows ]; then
		error "shell cmd is only supported on Windows"
	fi
	INTERPRETER="cmd"
	SHELL_ARGS=(/d /s /c)
	;;
*)
	error "unsupported shell '$SHELL_TYPE'. Use bash, sh, python, pwsh, powershell or cmd."
	;;
esac

if ! command -v "$INTERPRETER" >/dev/null 2>&1; then
	error "shell '$INTERPRETER' was not found on this runner"
fi

# --- ⏱️ Timeout -------------------------------------------------------------

CHILD_PID=
if command -v pgrep >/dev/null 2>&1; then HAVE_PGREP=1; else HAVE_PGREP=0; fi

# Print the pid and all children. Children come first.
collect_tree() {
	local pid=$1 kid
	for kid in $(pgrep -P "$pid" 2>/dev/null || true); do
		collect_tree "$kid"
	done
	printf '%s\n' "$pid"
}

# Stop the command and its children. Try TERM first, then KILL.
kill_tree() {
	local pid=$1 pids i

	if [ "$HAVE_PGREP" -eq 0 ]; then
		# shortcut: Git Bash has no pgrep, so kill the direct child only.
		# Grandchildren can survive. Upgrade to tree-kill in Node if this matters.
		kill -TERM "$pid" 2>/dev/null || true
		sleep 0.1
		kill -KILL "$pid" 2>/dev/null || true
		return 0
	fi

	pids=$(collect_tree "$pid" | tr '\n' ' ')
	# shellcheck disable=SC2086
	kill -TERM $pids 2>/dev/null || true

	# Wait up to 1s for a clean exit.
	i=0
	while [ "$i" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
		sleep 0.1
		i=$((i + 1))
	done

	# shellcheck disable=SC2086
	kill -KILL $pids 2>/dev/null || true
}

# Set $timed_out. Return the exit code. Return 124 on timeout.
timed_out=0

run_command() {
	local cmd=$1 start code tick poll_ticks

	timed_out=0

	if [ "$TIMEOUT" -eq 0 ]; then
		"$INTERPRETER" "${SHELL_ARGS[@]}" "$cmd"
		return $?
	fi

	# Run in the background, so we can stop the command on timeout.
	"$INTERPRETER" "${SHELL_ARGS[@]}" "$cmd" &
	CHILD_PID=$!
	start=$SECONDS
	tick=0
	poll_ticks=$((POLL * 10))

	# Check for exit every 0.1s. Check the timeout every polling interval.
	while kill -0 "$CHILD_PID" 2>/dev/null; do
		sleep 0.1
		tick=$((tick + 1))
		if [ "$tick" -ge "$poll_ticks" ]; then
			tick=0
			if [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then
				timed_out=1
				kill_tree "$CHILD_PID"
				break
			fi
		fi
	done

	code=0
	wait "$CHILD_PID" 2>/dev/null || code=$?
	CHILD_PID=

	if [ "$timed_out" -eq 1 ]; then
		code=124
	fi

	return "$code"
}

# Decide if the next attempt must run.
should_retry() {
	local code=$1 was_timeout=$2

	# retry_on_exit_code replaces retry_on.
	if [ -n "$RETRY_ON_EXIT_CODE" ]; then
		[ "$code" -eq "$RETRY_ON_EXIT_CODE" ]
		return
	fi

	case $RETRY_ON in
	any) return 0 ;;
	error)
		[ "$was_timeout" -eq 0 ] || return 1
		[ "$code" -ne 0 ]
		return
		;;
	timeout)
		[ "$was_timeout" -eq 1 ]
		return
		;;
	esac
}

# Stop the child when the job is cancelled.
on_signal() {
	if [ -n "$CHILD_PID" ]; then
		kill_tree "$CHILD_PID"
	fi
	exit 130
}
trap on_signal INT TERM

# --- 🔄 Retry loop ----------------------------------------------------------

ATTEMPT=1
TOTAL_ATTEMPTS=0
EXIT_CODE=0
FAIL_REASON=
SUMMARY_ROWS=
START_TIME=$SECONDS

# Do not print the command. It can contain secrets.
debug "shell=$INTERPRETER timeout=${TIMEOUT}s attempts=$MAX_ATTEMPTS retry_on=$RETRY_ON"

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
	echo "::group::🔄 Attempt $ATTEMPT/$MAX_ATTEMPTS"

	CMD=$COMMAND
	if [ "$ATTEMPT" -gt 1 ] && [ -n "$NEW_COMMAND_ON_RETRY" ]; then
		CMD=$NEW_COMMAND_ON_RETRY
	fi

	ATTEMPT_START=$SECONDS
	set +e
	run_command "$CMD"
	EXIT_CODE=$?
	set -e
	ATTEMPT_DURATION=$((SECONDS - ATTEMPT_START))
	TOTAL_ATTEMPTS=$ATTEMPT

	if [ "$EXIT_CODE" -eq 0 ]; then
		SUMMARY_ROWS="${SUMMARY_ROWS}| $ATTEMPT | ✅ success | ${ATTEMPT_DURATION}s |"$'\n'
		echo "::endgroup::"
		if [ "$ATTEMPT" -gt 1 ]; then
			notice "Command succeeded after $ATTEMPT attempts."
		fi
		break
	fi

	if [ "$timed_out" -eq 1 ]; then
		REASON="Timeout after ${TIMEOUT}s"
		SUMMARY_ROWS="${SUMMARY_ROWS}| $ATTEMPT | ⏱️ timeout | ${ATTEMPT_DURATION}s |"$'\n'
	else
		REASON="Exit code $EXIT_CODE"
		SUMMARY_ROWS="${SUMMARY_ROWS}| $ATTEMPT | ❌ exit $EXIT_CODE | ${ATTEMPT_DURATION}s |"$'\n'
	fi

	if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ] || ! should_retry "$EXIT_CODE" "$timed_out"; then
		FAIL_REASON="Final attempt failed. $REASON"
		echo "::endgroup::"
		break
	fi

	if [ "$WARNING_ON_RETRY" = true ]; then
		warn "Attempt $ATTEMPT failed. Reason: $REASON"
	else
		echo "⚠️ Attempt $ATTEMPT failed. Reason: $REASON"
	fi
	echo "::endgroup::"

	WAIT_TIME=$RETRY_WAIT
	if [ "$EXPONENTIAL_BACKOFF" = true ]; then
		EXP=$((ATTEMPT - 1))
		if [ "$EXP" -gt 10 ]; then
			EXP=10
		fi
		WAIT_TIME=$((RETRY_WAIT * (2 ** EXP)))
		if [ "$WAIT_TIME" -gt "$MAX_RETRY_WAIT" ]; then
			WAIT_TIME=$MAX_RETRY_WAIT
		fi
	fi
	if [ "$WAIT_TIME" -gt 0 ]; then
		echo "⏳ Retrying in ${WAIT_TIME}s..."
		sleep "$WAIT_TIME"
	fi

	if [ -n "$ON_RETRY_COMMAND" ]; then
		set +e
		"$INTERPRETER" "${SHELL_ARGS[@]}" "$ON_RETRY_COMMAND"
		CLEANUP_CODE=$?
		set -e
		if [ "$CLEANUP_CODE" -ne 0 ]; then
			warn "Retry command failed with exit code $CLEANUP_CODE."
		fi
	fi

	ATTEMPT=$((ATTEMPT + 1))
done

# --- 📤 Results -------------------------------------------------------------

DURATION=$((SECONDS - START_TIME))

write_output total_attempts "$TOTAL_ATTEMPTS"
write_output exit_code "$EXIT_CODE"
write_output duration_seconds "$DURATION"
if [ -n "$FAIL_REASON" ]; then
	write_multiline_output exit_error "$FAIL_REASON"
else
	write_output exit_error ""
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### 🔄 Rerun"
		echo
		echo "| Attempt | Result | Duration |"
		echo "| --- | --- | --- |"
		printf '%s' "$SUMMARY_ROWS"
	} >>"$GITHUB_STEP_SUMMARY"
fi

if [ -n "$FAIL_REASON" ]; then
	if [ "$CONTINUE_ON_ERROR" = true ]; then
		warn "$FAIL_REASON"
		exit 0
	fi
	echo "::error::❌ $FAIL_REASON" >&2
	exit "$EXIT_CODE"
fi

echo "✅ Command succeeded after $TOTAL_ATTEMPTS attempt(s)."
exit 0
