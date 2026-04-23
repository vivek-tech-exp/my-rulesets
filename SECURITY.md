# Security Policy

## Supported Versions

Currently, only the latest version of `gh-ruleset-sync` is supported for security updates.

| Version | Supported          |
| ------- | ------------------ |
| v1.1.x  | :white_check_mark: |
| < v1.1  | :x:                |

## Reporting a Vulnerability

**Please do not open a public issue for security vulnerabilities.**

`gh-ruleset-sync` leverages GitHub's **Private Vulnerability Reporting**. To report a vulnerability:

1. Navigate to the [Security tab](https://github.com/vivek-tech-exp/gh-ruleset-sync/security) of this repository.
2. Under "Vulnerability reporting", click on "Report a vulnerability" to open a private advisory.

GitHub will automatically notify the maintainers. We strive to acknowledge reports within 48 hours and provide a fix or mitigation plan within 10 business days.

### Important Note on PATs

`gh-ruleset-sync` handles Personal Access Tokens (PATs) for repository administration. 
- Always use the minimum necessary scope for your PATs (`repo`, `admin:org`).
- Never hardcode PATs in scripts or configuration files.
- Use GitHub Actions Secrets or environment variables to inject tokens at runtime.
- If you believe a PAT has been leaked due to a tool behavior, revoke the token immediately.
