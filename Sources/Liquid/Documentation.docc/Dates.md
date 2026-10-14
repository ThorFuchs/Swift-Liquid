# Date filtering

Format complete calendar dates, epoch seconds, and timestamps with explicit offsets.

## Overview

```swift
let output = try await LiquidEngine().render(
    template: "{{ stamp | date: '%F %T %:z %N' }}",
    context: ["stamp": "2024-02-03T04:05:06.123456789+05:30"]
)
// 2024-02-03 04:05:06 +05:30 123456789
```

Integers and strings of ASCII digits are whole-second epochs. `now` and `today`
use the current clock. An empty or nil format preserves the input, including its
type. Floats and unparseable strings also retain their values.

Complete ISO, ordinal, English-month, RFC, and asctime dates are accepted.
Timezone-free dates use UTC; fixed offsets are preserved for formatting. Slash
dates with the year last use day/month/year. The calendar is proleptic Gregorian.
Ruby Time's complete heuristic grammar, including missing date components, still
requires further qualification.

`%N` retains nine parsed fractional digits, `%L` retains three, and a width selects
another precision. `%:z` prints an offset with a colon. Unknown directives remain
literal. Field width and fractional precision are bounded to 1,024, years to
1…9999, and formatting consumes the invocation's render and output budgets.

See <doc:LimitsAndConcurrency> for operational limits and ``LiquidError`` for
failure handling.
