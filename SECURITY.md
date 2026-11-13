# Security

Found a security or privacy problem in Nina? Please report it privately:
**Security → Report a vulnerability** on this repository (GitHub private vulnerability reporting).
Please don't open a public issue for it.

What Nina does with data is described in [docs/HEALTH.md](docs/HEALTH.md) and in the app
(Settings → iCloud & Data → Where your data lives): the diary syncs only through the user's own
private iCloud database; Apple Health values are read live and never stored by Nina; barcode lookups
send only the barcode number to Open Food Facts; there are no Nina servers or accounts.
