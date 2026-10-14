# Dates and time zones

The `date` filter uses Shopify's input and format coercion rules. A Swift integer
or a string containing only ASCII digits is an epoch in whole seconds. `now` and
`today` use the current clock. Floats, booleans, nil, arrays, and unparseable strings
retain their original value. An empty or nil format also preserves the input's
type, so subsequent filters see the same value. Other format arguments are
converted to Liquid strings.

```liquid
{{ '2024-02-03T04:05:06.123456789+05:30' | date: '%F %T %:z %N' }}
```

Produces `2024-02-03 04:05:06 +05:30 123456789`.

## Complete date forms

The parser accepts these complete forms, with optional times where applicable:

| Form | Example |
| --- | --- |
| Calendar date | `2024-02-03`, `2024/02/03`, `2024-2-3` |
| Day-first date | `03/02/2024`, `03.02.2024` |
| Two-digit year | `03-Feb-68` → 2068, `03-Feb-69` → 1969 |
| Ordinal date | `2024-034` → February 3 |
| ISO timestamp | `2024-02-03T04:05:06Z`, `20240203T040506Z` |
| English month | `February 3, 2024 4:05 pm`, `3 February 2024` |
| RFC date | `Sat, 03 Feb 2024 04:05:06 +0530` |
| asctime | `Fri Jul 16 01:00:00 2004` |

Slash dates with the year last use **day/month/year**, matching the reference.
English month and weekday names are case-insensitive. Missing seconds default to
zero. Calendar arithmetic uses the proleptic Gregorian calendar, including before
1582. Like Ruby Time, days 29–31 can overflow a short month; February 31, 2024
normalizes to March 2. A valid `24:00:00` advances one day and a second value of 60
normalizes into the next minute. Invalid components retain the original input.

Timezone-free input uses UTC. Numeric offsets accept hours, minutes, and seconds,
including `+05`, `+0530`, and `+05:30:45`. RFC 822 abbreviations and military letters
are recognized. An unrecognized abbreviation is ignored in UTC, matching the
pinned reference's UTC execution environment. The process's local timezone does
not change these rules. `%Z` is `UTC` at offset zero and empty for other fixed
offsets.

## Formatting

The formatter supports calendar fields, English names, ordinal days, weekday and
week numbers, ISO week years, epoch seconds, composite date/time directives, and
literal text. Numeric directives support `-`, `_`, `0`, and field widths. `^` and
`#` follow the reference's directive-specific case rules. Supported `E` and `O`
modifiers use the reference's English representation. Unknown directives remain
literal, including `%Q` and `%+`.

`%z`, `%:z`, `%::z`, and `%:::z` produce offsets as `+0530`, `+05:30`,
`+05:30:00`, and the shortest complete offset respectively. `%L` defaults to three
fractional digits and `%N` to nine. A width selects the fractional precision;
`%12N` can retain twelve parsed digits. Parsed fractions use their decimal
spelling, avoiding a conversion through binary floating point. Epoch seconds
are integral and `%s` floors pre-epoch fractional timestamps correctly.

Field widths and fractional precision are bounded to 1,024. Recognized dates are
bounded to calendar years 1…9999. Formatting charges the invocation's render-step
budget and checks UTF-8 output capacity before appending. Range and quota failures
are operational errors, not evidence that a Liquid program is syntactically invalid.

## Remaining reference differences

Ruby's full heuristic `Time.parse` grammar is not implemented. In particular,
dates with missing components, prose with embedded date fragments, and broader
locale-dependent spellings need further qualification. Complete compatibility
must not be inferred from the date fixture count. See
[compatibility evidence](Conformance.md) for the exact observed results and the
remaining stable-release gates.
