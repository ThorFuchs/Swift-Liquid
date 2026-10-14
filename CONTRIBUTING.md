# Contributing

Use Swift 6.4 and language mode 6. Start with the language contract and the area
you are changing. Keep fixes focused; include a regression case that demonstrates
the behavior using public APIs.

```sh
python3 Scripts/ci.py --lane native
python3 Scripts/ci.py --lane docs
```

For runtime changes, also run the performance lane on an idle host. Describe the
trigger, resulting behavior, checks run, and any remaining limits. Do not revise
fixture expectations to make a failing implementation pass. Update a corpus pin
only with its complete license, checksum, observed count, and reference review.

Original contributions are Apache-2.0. Retain attribution and modification
notices on adapted files. Keep credentials and private input data out of issues,
tests, documentation, and archives.
