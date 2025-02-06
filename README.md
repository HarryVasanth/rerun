# Rerun Action

This GitHub action retries a command with configurable timeout handling and retry logic. It's designed to be lightweight, fast, and compatible across different environments.

## Features

- Configurable timeout in minutes or seconds
- Adjustable number of retry attempts
- Support for various shells (bash, sh, cmd, powershell)
- Option to run cleanup commands between retries
- Ability to change command on subsequent attempts
- Lightweight implementation using Bash in a minimal Alpine Docker container

## Inputs

| Input                  | Description                              | Required | Default |
| ---------------------- | ---------------------------------------- | -------- | ------- |
| `timeout_minutes`      | Minutes to wait before attempt times out | No       | N/A     |
| `timeout_seconds`      | Seconds to wait before attempt times out | No       | N/A     |
| `max_attempts`         | Number of attempts to make               | Yes      | N/A     |
| `command`              | Command to execute                       | Yes      | N/A     |
| `retry_wait_seconds`   | Seconds between retries                  | No       | 10      |
| `shell`                | Shell to use                             | No       | bash    |
| `retry_on`             | Retry on error/timeout/any               | No       | any     |
| `on_retry_command`     | Command to run before retry              | No       | N/A     |
| `new_command_on_retry` | New command for subsequent attempts      | No       | N/A     |
| `continue_on_error`    | Continue workflow on error               | No       | false   |

## Outputs

| Output           | Description         |
| ---------------- | ------------------- |
| `total_attempts` | Total attempts made |
| `exit_code`      | Final exit code     |
| `exit_error`     | Final error message |

## Usage

### Basic retry

```yaml
- uses: harryvasanth/rerun@v1
  with:
    timeout_seconds: 30
    max_attempts: 3
    command: "apt-get update"
```

### Retry with cleanup

```yaml
- uses: harryvasanth/rerun@v1
  with:
    max_attempts: 5
    command: "dpkg -i package.deb"
    on_retry_command: "dpkg --remove package"
```

### Different command on retry

```yaml
- uses: harryvasanth/rerun@v1
  with:
    max_attempts: 3
    command: "apt-get install -y some-package"
    new_command_on_retry: "apt-get install -y some-package --no-install-recommends"
```

## Example

Retry a potentially flaky Debian package installation:

```yaml
jobs:
  install:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Update package lists
        run: sudo apt-get update
      - name: Install package with retry
        uses: harryvasanth/rerun@v1
        with:
          timeout_minutes: 5
          max_attempts: 3
          command: sudo apt-get install -y potentially-flaky-package
          retry_wait_seconds: 30
```
