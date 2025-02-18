# 🔄 Rerun Action

This GitHub Action retries a command with configurable timeout handling, retry logic, and optional **exponential backoff**. It's designed to be lightweight, fast, and compatible across different environments! 🌍

## ✨ Features

- ⏱️ Configurable timeout in minutes or seconds.
- 📈 **Exponential backoff** support to gracefully handle rate limits or network issues.
- 🔄 Adjustable number of retry attempts.
- 🐚 Support for various shells (bash, sh, cmd, powershell).
- 🧹 Option to run cleanup commands between retries.
- ✨ Ability to swap the execution command on subsequent attempts.
- 🪶 Lightweight implementation using Bash in a minimal Alpine Docker container.

## 📥 Inputs

| Input                  | Description                                                   | Required | Default |
| ---------------------- | ------------------------------------------------------------- | -------- | ------- |
| `timeout_minutes`      | ⏱️ Minutes to wait before attempt times out                   | No       | N/A     |
| `timeout_seconds`      | ⏱️ Seconds to wait before attempt times out                   | No       | N/A     |
| `max_attempts`         | 🔢 Number of attempts to make                                 | Yes      | N/A     |
| `command`              | 💻 Command to execute                                         | Yes      | N/A     |
| `retry_wait_seconds`   | ⏳ Seconds between retries (Base wait if using backoff)       | No       | 10      |
| `exponential_backoff`  | 📈 Wait time doubles after each failed attempt (`true/false`) | No       | false   |
| `shell`                | 🐚 Shell to use                                               | No       | bash    |
| `retry_on`             | 🎯 Retry on `error` / `timeout` / `any`                       | No       | any     |
| `on_retry_command`     | 🧹 Command to run before retry (e.g., reset state)            | No       | N/A     |
| `new_command_on_retry` | ✨ Alternative command for subsequent attempts                | No       | N/A     |
| `continue_on_error`    | ⏭️ Continue workflow on error (`true/false`)                  | No       | false   |

## 📤 Outputs

| Output           | Description            |
| ---------------- | ---------------------- |
| `total_attempts` | 🔢 Total attempts made |
| `exit_code`      | 🚪 Final exit code     |
| `exit_error`     | ❌ Final error message |

## 🛠️ Usage

### 🔄 Basic retry

```yaml
- uses: harryvasanth/rerun@v1
  with:
    timeout_seconds: 30
    max_attempts: 3
    command: "apt-get update"
```

### 📈 Retry with Exponential Backoff

```yaml
- uses: harryvasanth/rerun@v1
  with:
    max_attempts: 4
    command: "curl -f [https://api.flaky-service.com/data](https://api.flaky-service.com/data)"
    retry_wait_seconds: 5
    exponential_backoff: "true" # Waits 5s, then 10s, then 20s
```

### 🧹 Retry with cleanup

```yaml
- uses: harryvasanth/rerun@v1
  with:
    max_attempts: 5
    command: "dpkg -i package.deb"
    on_retry_command: "dpkg --remove package"
```

### ✨ Different command on retry

```yaml
- uses: harryvasanth/rerun@v1
  with:
    max_attempts: 3
    command: "apt-get install -y some-package"
    new_command_on_retry: "apt-get install -y some-package --no-install-recommends"
```

## 📝 Example Scenario

Retry a potentially flaky Debian package installation with a longer timeout and exponential backoff:

```yaml
jobs:
  install:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 📦 Update package lists
        run: sudo apt-get update
      - name: 🚀 Install package with smart retry
        uses: harryvasanth/rerun@v1
        with:
          timeout_minutes: 5
          max_attempts: 3
          command: sudo apt-get install -y potentially-flaky-package
          retry_wait_seconds: 15
          exponential_backoff: "true"
```

## 💻 Standalone Usage (via curl)

You don't have to be in GitHub Actions to use `rerun.sh`! You can download and run it directly in any terminal, script, or alternative CI/CD system.

Since the script relies on environment variables (prefixed with `INPUT_`), you can execute it like this:

```bash
# 1. Download the script and make it executable
curl -sO https://raw.githubusercontent.com/harryvasanth/rerun/main/rerun.sh
chmod +x rerun.sh

# 2. Run your flaky command with environment variables
INPUT_MAX_ATTEMPTS=3 \
INPUT_RETRY_WAIT_SECONDS=5 \
INPUT_EXPONENTIAL_BACKOFF=true \
INPUT_COMMAND="npm test" \
./rerun.sh

```

Alternatively, you can run it entirely in one line without saving the file:

```bash
export INPUT_MAX_ATTEMPTS=3
export INPUT_COMMAND="curl -sS https://httpbin.org/delay/1"
curl -s https://raw.githubusercontent.com/harryvasanth/rerun/main/rerun.sh | bash

```
