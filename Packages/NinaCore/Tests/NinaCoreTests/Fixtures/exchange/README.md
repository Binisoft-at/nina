# Exchange fixtures (Binisoft exchange, format v1)

Copied unchanged from Thalia's test files (`Packages/ThaliaCore/Tests/ThaliaCoreTests/Fixtures/exchange`),
laid out like the shared App Group `group.at.binisoft.shared`. Neutral example data only.
`ThaliaExchangeTests.swift` reads them:

- `Nina/exchange/days/2026-11-22.json` – a file for Thalia's reader: values per entry, a date with
  fractions, an unknown metric (`fiber_g`) and a value from Health. Nina itself writes one total per
  metric and day, without fractions, without `fiber_g` and without Health values.
- `Demo/exchange/` – Thalia's demo source: `source.json` and a day with `kcal` and `protein_g`
  totals, the shape Nina writes.
- `Theo/exchange/source.json`, `George/exchange/source.json` – the shape of `source.json`.
- `Thalia/exchange/catalog.json` – Thalia's structure (goals, categories, measures, results).
