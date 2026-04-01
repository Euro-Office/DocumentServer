# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

As Euro-Office is in active early development, security fixes are applied to the latest version on the `main` branch.

## Reporting a Vulnerability

If you discover a security vulnerability in Euro-Office, please report it responsibly. **Do not open a public issue.**

### How to Report

1. **GitHub Private Vulnerability Reporting**: Use [GitHub's security advisory feature](https://github.com/Euro-Office/DocumentServer/security/advisories/new) to submit a private report.
2. **Email**: If you prefer email, contact the maintainers directly (see organization profile).

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Affected component(s) and version(s)
- Potential impact assessment
- Suggested fix (if available)

### What to Expect

- **Acknowledgment**: Within 48 hours of your report.
- **Assessment**: The team will evaluate severity and impact within 7 days.
- **Fix Timeline**: Critical vulnerabilities will be prioritized for immediate patching. Other issues will be addressed based on severity.
- **Disclosure**: We follow coordinated disclosure. Once a fix is released, we will credit the reporter (unless anonymity is requested) and publish an advisory.

## Scope

This policy covers all repositories under the [Euro-Office](https://github.com/Euro-Office) organization, including but not limited to:

- **DocumentServer** — orchestration and deployment
- **server** — Node.js backend (DocService, FileConverter, SpellChecker)
- **core** — document conversion engine
- **web-apps** — frontend editors
- **sdkjs** — JavaScript SDK
- **desktop-apps** / **DesktopEditors** — desktop application

## Security Considerations

Euro-Office inherits code from the OnlyOffice project. Known CVEs affecting upstream OnlyOffice versions may also affect Euro-Office. If you are aware of an upstream vulnerability that has not been addressed here, please report it using the process above.

## Acknowledgments

We appreciate the security research community's efforts in helping keep Euro-Office and its users safe.
