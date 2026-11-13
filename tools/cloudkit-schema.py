#!/usr/bin/env python3
"""Writes cloudkit/schema.ckdb from the synced SwiftData models in Shared/Model/Models.swift.

SwiftData mirrors each @Model as record type CD_<Model>: attributes as CD_<name>, to-one
relationships as CD_<name> STRING (the related record's name), to-many sides are not stored.
usage: python3 tools/cloudkit-schema.py [--check]   (--check: fail if the file is out of date)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "Shared/Model/Models.swift"
SCHEMA = ROOT / "cloudkit/schema.ckdb"
TYPES = {"String": "STRING", "Int": "INT64", "Double": "DOUBLE", "Bool": "INT64", "Date": "TIMESTAMP", "UUID": "STRING"}

HEADER = """// Nina – CloudKit schema of iCloud.at.binisoft.nina (SwiftData mirroring: CD_ prefix, one
// record type per @Model, to-one relationships as CD_<name> STRING, to-many sides are not stored).
//
// Generated from Shared/Model/Models.swift by tools/cloudkit-schema.py – run it after every model
// change. Order on every model change:
//   1. add the field to the model   2. python3 tools/cloudkit-schema.py   3. Actions → CloudKit schema
//   4. CloudKit Console → Deploy Schema Changes to Production   5. then the TestFlight build.
// Production only accepts additive changes: never rename or remove a field.

DEFINE SCHEMA
"""

USERS = """    RECORD TYPE Users (
        "___createTime" TIMESTAMP,
        "___createdBy"  REFERENCE,
        "___etag"       STRING,
        "___modTime"    TIMESTAMP,
        "___modifiedBy" REFERENCE,
        "___recordID"   REFERENCE,
        roles           LIST<INT64>,
        GRANT WRITE TO "_creator",
        GRANT READ TO "_world"
    );"""


def build() -> str:
    source = MODELS.read_text()
    models = re.findall(r"@Model\s+final class (\w+)\s*\{(.*?)\n\}", source, re.S)
    names = {name for name, _ in models}
    blocks = []
    for name, body in sorted(models):
        fields = {"CD_entityName": "STRING"}
        for match in re.finditer(r"^    var (\w+): ([\w\[\]]+)(\?)?", body, re.M):
            attribute, kind = match.group(1), match.group(2)
            if kind.startswith("["):
                continue  # to-many relationship: not stored on this side
            if kind in names:
                fields["CD_" + attribute] = "STRING"
            elif kind in TYPES:
                fields["CD_" + attribute] = TYPES[kind]
            else:
                raise SystemExit(f"unknown type {kind} in {name}.{attribute}")
        lines = ['        "___createTime" TIMESTAMP,', '        "___createdBy"  REFERENCE,', '        "___etag"       STRING,',
                 '        "___modTime"    TIMESTAMP,', '        "___modifiedBy" REFERENCE,', '        "___recordID"   REFERENCE QUERYABLE,']
        width = max(len(key) for key in fields)
        for key in sorted(fields):
            lines.append(f"        {key.ljust(width)} {fields[key]},")
        lines += ['        GRANT WRITE TO "_creator",', '        GRANT CREATE TO "_icloud",', '        GRANT READ TO "_world"']
        blocks.append(f"    RECORD TYPE CD_{name} (\n" + "\n".join(lines) + "\n    );")
    return HEADER + "\n" + "\n\n".join(blocks + [USERS]) + "\n"


if __name__ == "__main__":
    text = build()
    if "--check" in sys.argv:
        if SCHEMA.read_text() != text:
            raise SystemExit("cloudkit/schema.ckdb is out of date: run python3 tools/cloudkit-schema.py")
        print("cloudkit/schema.ckdb is up to date")
    else:
        SCHEMA.write_text(text)
        print(f"wrote {SCHEMA.relative_to(ROOT)}")
