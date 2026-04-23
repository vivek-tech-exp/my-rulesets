# Contributing to gh-ruleset-sync

Thanks for considering a contribution. This guide covers the workflow and expectations.

## Prerequisites

- **Bash 4+** (macOS ships Bash 3; install a newer version via `brew install bash`)
- **[GitHub CLI](https://cli.github.com/)** (`gh`) — authenticated via `gh auth login`
- **[jq](https://stedolan.github.io/jq/)** — JSON processor
- **[Bats](https://github.com/bats-core/bats-core)** — test framework for Bash
- **[ShellCheck](https://www.shellcheck.net/)** — static analysis for shell scripts

## Local Setup

```bash
# Clone the repo
git clone https://github.com/vivek-tech-exp/gh-ruleset-sync.git
cd gh-ruleset-sync

# Make scripts executable
chmod +x gh-ruleset-sync internal/*.sh

# Verify the CLI loads
./gh-ruleset-sync --help
```

## Running Tests

The test suite uses [Bats](https://github.com/bats-core/bats-core) with `bats-support` and `bats-assert` libraries.

```bash
# Install Bats libraries (one-time)
mkdir -p /tmp/bats-libs
git clone --depth 1 https://github.com/bats-core/bats-support.git /tmp/bats-libs/bats-support
git clone --depth 1 https://github.com/bats-core/bats-assert.git /tmp/bats-libs/bats-assert

# Run the full suite
BATS_LIB_PATH=/tmp/bats-libs bats --recursive tests

# Run ShellCheck
find . -type f \( -name '*.sh' -o -name '*.bash' \) -print0 | xargs -0 shellcheck -x -S warning
```

Both checks run automatically in CI on every push and pull request.

## Making Changes

### Branch Naming

Use a prefix that matches the type of change:

| Prefix | Use for |
|:---|:---|
| `fe/` or `feature/` | New features |
| `fix/` | Bug fixes |
| `patch/` | Small, targeted improvements |
| `docs/` | Documentation-only changes |

### Pull Request Expectations

1. **One logical change per PR.** Don't bundle unrelated fixes.
2. **ShellCheck clean.** Zero warnings at the `warning` severity level.
3. **Tests pass.** Add tests for new logic when practical.
4. **Use `--dry-run` when testing against live repos.** Never run mutating commands against repos you don't own.
5. **Link the related issue** if one exists.

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) style:

```
feat: add --exclude flag for audit command
fix: handle empty API response in capture flow
docs: clarify Smart Matrix tier overlap
chore: update ShellCheck to latest in CI
```

## Editing Policies

Files under `policies/` are production configuration. Changes to these JSON files trigger the CI sync workflow. Treat policy changes the same way you'd treat infrastructure changes — review carefully and test with `--dry-run` first.

## Reporting Issues

Use the issue templates when filing bugs or requesting features. If you've found a security vulnerability, **do not open a public issue** — see [SECURITY.md](SECURITY.md) instead.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
