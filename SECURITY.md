# Security Policy

## Supported Versions

Security updates are currently provided for the latest version on the `main` branch.

| Version | Supported |
| ------- | --------- |
| main    | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it privately rather than opening a public GitHub issue.

When reporting a vulnerability, please include:

- A clear description of the issue
- Steps to reproduce the vulnerability
- The potential security impact
- Relevant logs, requests, or proof-of-concept details when safe to provide

Please avoid including real API keys, passwords, tokens, or other sensitive information in the report.

## Security Considerations

This project includes security-related mechanisms such as:

- API key authentication
- API key enable/disable controls
- Per-key rate limiting
- Structured authentication errors
- Request ID propagation
- Input validation
- Backend timeout controls
- Local model isolation

This project is intended as a technical reference and development foundation. Additional hardening should be performed before using it in a production environment.

## Responsible Disclosure

Please allow reasonable time for a vulnerability to be investigated and addressed before publicly disclosing security-sensitive details.
