# Nina – import format

Import & Export (Settings, the "+" sheet, or any empty screen → Import my data) reads a CSV:

```csv
id,title,notes,done,folder
1,Water the plants,,,Home
2,Send the invoice,"Before Friday, please",yes,Work
```

| Column | Meaning | Required |
|---|---|---|
| `id` | Stable id of the row (any text). Re-importing a row with the same id updates the item. | no |
| `title` | What the item is | **yes** |
| `notes` | Longer text, may contain line breaks (in quotes) | no |
| `done` | `yes` / `x` / `1` / `true` / `ja` / `✓` = done | no |
| `folder` | Folder name; created if it doesn't exist; empty = no folder | no |

- Comma, semicolon, tab or `|` as separator (detected); UTF-8, UTF-16 or Windows-1252.
- Rows without a title are skipped and listed in the preview.
- Without an `id` column, title + folder identify a row – importing the same file twice still
  changes nothing.
- **Preview first**: "3 new · 1 updated · 5 unchanged · 1 skipped"; nothing changes until Import.
- **Export** writes the same format with each item's id, so a file can be edited anywhere and
  imported again.
- Everything is read on the device.

## AI import

"Copy Prompt for Another AI" copies a prompt with the columns, the rules, an example and the
existing folder names. Paste it with your notes, a screenshot or a spreadsheet into any AI, paste
the CSV it answers with into the import screen, preview, import. The prompt lives in
`Packages/NinaCore/Sources/NinaCore/ItemCSV.swift` (`ItemCSV.prompt`).
