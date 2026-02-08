# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | ✅ Active support  |
| < 0.1   | ❌ Not applicable  |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in Cortex, please report it responsibly.

### How to Report

**DO NOT** open a public GitHub issue for security vulnerabilities.

Instead, please report security issues by email to:

📧 **security@cortexai.dev** (or create a [private security advisory](https://github.com/cortexai-memory/cortex/security/advisories/new))

### What to Include

Please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)
- Your contact information

### Response Timeline

- **Initial response**: Within 48 hours
- **Status update**: Within 7 days
- **Fix timeline**: Depends on severity
  - Critical: 24-48 hours
  - High: 7 days
  - Medium: 30 days
  - Low: Next release

### Security Considerations

Cortex is designed with security in mind:

1. **No external network calls** - All data stays local
2. **JSON construction via jq** - Prevents injection attacks
3. **Atomic file writes** - Prevents corruption
4. **CI/CD detection** - Hooks skip in automated environments
5. **Local-only storage** - `.cortex/` never committed to repos

### Known Security Features

- ✅ Input sanitization via jq for all JSON
- ✅ Exit 0 in hooks to never block git
- ✅ No eval or dynamic code execution
- ✅ ShellCheck compliance (zero warnings)
- ✅ File permissions properly set (644/755)

### Out of Scope

The following are explicitly out of scope:

- Social engineering attacks
- Physical access to user's machine
- Compromise of underlying OS or shell
- Git repository vulnerabilities (not specific to Cortex)

## Security Updates

Security updates will be:

1. Released as patch versions (e.g., 0.1.1)
2. Documented in CHANGELOG.md with `[SECURITY]` tag
3. Announced via GitHub security advisories
4. Backported to all supported versions

## Best Practices for Users

1. Keep Cortex updated: `cd cortex && git pull && ./install.sh`
2. Run health checks: `~/.cortex/bin/cortex-doctor.sh`
3. Review `.cortex/` is in your `.gitignore`
4. Use LLM enrichment only with trusted models
5. Protect API keys in `~/.cortex/config` (chmod 600)

## Acknowledgments

We thank security researchers who help keep Cortex safe for everyone.
