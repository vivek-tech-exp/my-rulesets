# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-04-19

### Added
- Fleet-wide `--rollback` safety feature for sync and delete operations.
- Production-hardened state management in `~/.config/gh-ruleset-sync/state/`.
- Bats test suite for automated logic verification.
- Context-aware audit suggestions based on account owner type (User vs. Org).
- Explicit logging for non-interactive fallback behaviors.

### Fixed
- Sanitized capture names to prevent path traversal vulnerabilities.
- Prevented dangerous personal account fallback in non-interactive sessions.
- Hardened API pagination logic for large repository lists.
- Implemented name-collision safety checks during sync.

## [1.0.1] - 2026-04-19

### Changed
- Set default `VISIBILITY` to 'all' for better enterprise fleet coverage.
- Enhanced `capture` argument parsing to support flexible flag ordering.

### Fixed
- Refactored audit logic to prevent false matches on ruleset names.

## [1.0.0] - 2026-04-19

### Added
- Initial release of `gh-ruleset-sync` as a GitHub CLI extension.
- Core commands: `sync`, `audit`, `capture`, `nuke`.
- Smart Matrix for intent-based policy deployment (`loose`, `moderate`, `strict`).
- Support for branch and tag rulesets.
- Built-in GitHub Actions workflow for GitOps automation.

[1.1.0]: https://github.com/vivek-tech-exp/gh-ruleset-sync/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/vivek-tech-exp/gh-ruleset-sync/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vivek-tech-exp/gh-ruleset-sync/releases/tag/v1.0.0
