# Security Policy

## Supported Versions

| Version               | Supported          |
| --------------------- | ------------------ |
| Latest stable release | :white_check_mark: |

Euro-Office is in active development. Security fixes are applied to the latest released version.

## Reporting a Vulnerability

If you discover a security vulnerability in Euro-Office, please report it responsibly. **Do not open a public issue.**

### How to Report

Use [GitHub's private vulnerability reporting](https://github.com/Euro-Office/DocumentServer/security/advisories/new) to submit a security advisory. This is the only channel for security reports and keeps the details private until a fix is available.

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Affected component(s) and version(s)
- Potential impact assessment
- Suggested fix (if available)

### Report Quality

- Keep reports short and concise. Include only the information needed to understand the threat and reproduce it, and do not overstate the impact.
- Do **not** include Personally Identifiable Information (PII) in your report. Redact or obfuscate any PII in your proof of concept (screenshots, server responses, JSON files, etc.) as much as possible. The same applies to secrets, keys, and credentials.
- If you used a large language model (LLM) to prepare the report, please disclose how. Review and edit any generated output before sending it, verify that your reproduction steps actually work, and confirm that everything in the report is valid and correct.
- All reports are validated manually. Submissions from automated tools (static analysis, AI, etc.) will not be considered unless you have manually reviewed and validated them first.

### What to Expect

- **Acknowledgment**: We aim to acknowledge your report within 5 business days.
- **Assessment**: The team will evaluate severity and impact and keep you informed of progress.
- **Fix Timeline**: Critical vulnerabilities are prioritized for patching. Other issues are addressed based on severity.
- **Disclosure**: We follow coordinated disclosure. Once a fix is released, we will publish an advisory and credit the reporter, unless anonymity is requested.

## Scope

This policy covers all repositories under the [Euro-Office](https://github.com/Euro-Office) organization.

## Security Considerations

Euro-Office inherits code from the OnlyOffice project. Known CVEs affecting upstream OnlyOffice versions may also affect Euro-Office. If you are aware of an upstream vulnerability that has not been addressed here, please report it using the process above.

## Acknowledgments

We appreciate the security research community's efforts in helping keep Euro-Office and its users safe.
