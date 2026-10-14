# Security reporting

Report vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/ThorFuchs/Swift-Liquid/security/advisories/new).
Avoid public disclosure of exploitable details or confidential input data.

The engine evaluates Liquid source without executing Swift or Ruby source code.
Partial sources are explicit; the library does not fetch URLs or read template
files. Resource limits and cancellation are operation controls, not a process
sandbox or a guarantee about process RSS. Applications remain responsible for
output escaping, input policy, and publication of rendered content.

During pre-1.0 development, report against the current main revision. Release
support policy will be recorded when 1.0 is published.
