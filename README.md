# 🔄 Rerun Action

Retry a command with a timeout, backoff and clear outputs.

No Docker. No Node. One bash script. It starts in milliseconds and it works on
GitHub-hosted and self-hosted runners.

## ✨ Why use this

- 🪶 **Lightweight.** No Node runtime and no image pull. The step starts at once.
- 📡 **Live output.** The command writes to the log as it runs. Logs do not wait.
- 🌳 **Clean timeout.** On timeout, the action stops the process tree, not only the direct child.
- 🌍 **Portable.** Linux, macOS and Windows (Git Bash).
- 📊 **Clear results.** Outputs for attempts, exit code and duration. A step summary table.
- 🔐 **No extra access.** No Docker socket. No token. No permissions.
- 🧯 **Safe logs.** The command is never printed, so secrets in it stay out of the log.

## 📥 Inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `timeout_minutes` | ⏱️ Minutes per attempt | No | none |
| `timeout_seconds` | ⏱️ Seconds per attempt | No | none |
| `max_attempts` | 🔢 Number of attempts | Yes | `3` |
| `command` | 💻 Command to run | Yes | none |
| `retry_wait_seconds` | ⏳ Wait between retries | No | `10` |
| `exponential_backoff` | 📈 Double the wait after each failure | No | `false` |
| `max_retry_wait_seconds` | 🛑 Cap for the backoff wait | No | `300` |
| `shell` | 🐚 `bash`, `sh`, `python`, `pwsh`, `powershell` or `cmd` | No | `bash` |
| `retry_on` | 🎯 Retry on `any`, `error` or `timeout` | No | `any` |
| `retry_on_exit_code` | 🎯 Retry only on this exit code. This replaces `retry_on` | No | none |
| `polling_interval_seconds` | 🔄 Seconds between timeout checks | No | `1` |
| `warning_on_retry` | ⚠️ Add a warning before each retry | No | `true` |
| `on_retry_command` | 🧹 Command to run before a retry | No | none |
| `new_command_on_retry` | ✨ Alternative command for the retries | No | none |
| `continue_on_error` | ⏭️ Do not fail the step when all attempts fail | No | `false` |

Set `timeout_minutes` or `timeout_seconds`. You can set both; the values add.
If you set neither, the command has no timeout. Set a timeout for commands that can hang.

## 📤 Outputs

| Output | Description |
| --- | --- |
| `total_attempts` | 🔢 Number of attempts made |
| `exit_code` | 🚪 Final exit code (`124` on timeout) |
| `exit_error` | ❌ Reason for the final failure |
| `duration_seconds` | ⏱️ Total time for all attempts and waits |

## 🛠️ Usage

### 🔄 Basic retry

```yaml
- uses: HarryVasanth/rerun@v1
  with:
    timeout_seconds: 30
    max_attempts: 3
    command: "apt-get update"
```

### 📈 Backoff with a cap

```yaml
- uses: HarryVasanth/rerun@v1
  with:
    max_attempts: 4
    retry_wait_seconds: 5
    max_retry_wait_seconds: 30
    exponential_backoff: "true" # Waits 5s, 10s, 20s. Never more than 30s.
    command: "curl -fsS https://api.example.com/data"
```

### 🧹 Cleanup before a retry

```yaml
- uses: HarryVasanth/rerun@v1
  with:
    max_attempts: 5
    command: "dpkg -i package.deb"
    on_retry_command: "dpkg --remove package"
```

### ✨ Different command on retry

```yaml
- uses: HarryVasanth/rerun@v1
  with:
    max_attempts: 3
    command: "apt-get install -y package"
    new_command_on_retry: "apt-get install -y package --no-install-recommends"
```

### 🎯 Retry one exit code

```yaml
- uses: HarryVasanth/rerun@v1
  with:
    max_attempts: 3
    retry_on_exit_code: 42
    command: "./flaky-tool"
```

### ⏭️ Continue after a failure

```yaml
- uses: HarryVasanth/rerun@v1
  id: deploy
  with:
    max_attempts: 2
    continue_on_error: "true"
    command: "./deploy.sh"

- run: echo "Exit code was ${{ steps.deploy.outputs.exit_code }}"
```

### 🐍 Python shell

```yaml
- uses: HarryVasanth/rerun@v1
  with:
    shell: python
    command: "import urllib.request; urllib.request.urlopen('https://example.com')"
```

## 🐚 Shell and OS support

| Shell | Linux | macOS | Windows |
| --- | --- | --- | --- |
| `bash` | ✅ | ✅ | ✅ (Git Bash) |
| `sh` | ✅ | ✅ | ❌ |
| `python` | ✅ | ✅ | ✅ |
| `pwsh` | ✅ | ✅ | ✅ |
| `powershell` | ❌ | ❌ | ✅ |
| `cmd` | ❌ | ❌ | ✅ |

## 🧪 Standalone use

Set the `INPUT_*` variables and run the script. This works outside GitHub Actions.

```bash
curl -fsSLO https://raw.githubusercontent.com/HarryVasanth/rerun/main/rerun.sh
chmod +x rerun.sh

INPUT_MAX_ATTEMPTS=3 \
INPUT_RETRY_WAIT_SECONDS=5 \
INPUT_TIMEOUT_SECONDS=60 \
INPUT_COMMAND="npm test" \
./rerun.sh
```

The script prints the outputs when `GITHUB_OUTPUT` is not set.

## 🔐 Security

- **No runtime downloads.** The action runs the script from its own repository.
- **No command echo.** The action does not print `command`, so secrets stay out of the log.
- **No Docker socket.** The action never asks for host access.
- **Least privilege.** No token and no permissions are needed.
- **Pin for production.** Use a commit SHA instead of `@v1`:

```yaml
- uses: HarryVasanth/rerun@<commit-sha> # v1
```

- **Limit the job.** Add `permissions: contents: read` to the workflow when the job needs nothing more.

## ⚠️ Limits

- Timeout checks run every `polling_interval_seconds` (default 1s). A timeout can be about 1s late.
- Git Bash on Windows has no `pgrep`. The action then stops the direct child only.
- The action streams output and does not capture it. `exit_error` is a short reason, not the full log.
- There is no retry on an output pattern. Use `retry_on_exit_code` or make the command exit with a code.

## 📄 License

MIT
