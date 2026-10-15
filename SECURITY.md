# Security reporting

Report vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/ThorFuchs/Swift-Liquid/security/advisories/new).
Avoid public disclosure of exploitable details or confidential input data.

The engine evaluates Liquid source without executing Swift or Ruby source code.
Partial sources are explicit; the library does not fetch URLs or read template
files. Resource limits and cancellation are operation controls, not a process
sandbox or a guarantee about process RSS. Applications remain responsible for
output escaping, input policy, and publication of rendered content.

Report against the latest published 1.x release or the current `main` revision.
Include the exact resolved commit, compiler/OS, minimal affected input and resource
profile. Fixes are developed on `main`; older release lines have no promised
backport window. Published tags remain unchanged. See [SUPPORT.md](SUPPORT.md)
for maintenance scope.
