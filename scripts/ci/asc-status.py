#!/usr/bin/env python3
"""Prints the latest App Store Connect builds of this app (processing state, TestFlight state,
platform, version, build number), the platforms on the app record, the TestFlight groups (testers
counted by state, never named) and the team's signing certificates. Read-only.

env: ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 (or ASC_KEY_PATH); BUNDLE_ID (default: APP_BUNDLE_ID
     from Config/Base.xcconfig). Synced from the Binisoft handbook.
"""
import os
import subprocess
import sys

import asc
import certificates

here = os.path.dirname(os.path.abspath(__file__))


def bundle_id():
    if os.environ.get("BUNDLE_ID"):
        return os.environ["BUNDLE_ID"]
    out = subprocess.run([sys.executable, os.path.join(here, "xcconfig.py"), "APP_BUNDLE_ID"],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def main():
    if not asc.has_key():
        sys.exit("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 are needed (repository secrets).")
    bundle = bundle_id()
    apps, _ = asc.get_all("/apps", {"filter[bundleId]": bundle})
    if not apps:
        print(f"No App Store Connect app with bundle ID {bundle}. Create it first (SETUP_CHECKLIST.md, section 3).")
        sys.exit(1)
    app = apps[0]
    print(f"App: {app['attributes']['name']} ({bundle}), id {app['id']}")
    on_record = asc.platforms(app["id"])
    print("Platforms on the record: " + (", ".join(f"{p} ({', '.join(v)})" for p, v in sorted(on_record.items())) or "none")
          + ("" if "MAC_OS" in on_record else "  (an app with a Mac version needs MAC_OS: 'App Store Connect platform' workflow)"))
    result = asc.request("GET", "/builds", {
        "filter[app]": app["id"], "sort": "-uploadedDate", "limit": "10",
        "include": "preReleaseVersion,buildBetaDetail",
        "fields[preReleaseVersions]": "version,platform",
        "fields[buildBetaDetails]": "internalBuildState,externalBuildState",
    })
    included = {(i["type"], i["id"]): i["attributes"] for i in result.get("included", [])}
    print(f"\nLatest builds ({len(result['data'])}):")
    for build in result["data"]:
        a = build["attributes"]
        rel = build.get("relationships", {})
        version_ref = (rel.get("preReleaseVersion", {}).get("data") or {})
        beta_ref = (rel.get("buildBetaDetail", {}).get("data") or {})
        version = included.get(("preReleaseVersions", version_ref.get("id")), {})
        beta = included.get(("buildBetaDetails", beta_ref.get("id")), {})
        print(f"- {version.get('platform', '?'):6} {version.get('version', '?')} ({a.get('version')}) · "
              f"uploaded {(a.get('uploadedDate') or '?')[:16]} · processing {a.get('processingState')} · "
              f"TestFlight {beta.get('internalBuildState', '?')} · expired {a.get('expired')}")
    print()
    testflight_groups(app["id"], [b["id"] for b in result["data"]])
    print()
    certificates.list_all()


def testflight_groups(app_id, build_ids):
    """Who can install: each TestFlight group, its testers' states (counted, never named – this
    output may be public) and which of the latest builds it has."""
    groups, _ = asc.get_all(f"/apps/{app_id}/betaGroups", {
        "fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds", "limit": "50"})
    print(f"TestFlight groups ({len(groups)}):")
    if not groups:
        print("- none – create one: SETUP_CHECKLIST 3.3")
    for group in groups:
        a = group["attributes"]
        testers, _ = asc.get_all(f"/betaGroups/{group['id']}/betaTesters", {"fields[betaTesters]": "state", "limit": "200"})
        states = {}
        for tester in testers:
            state = tester["attributes"].get("state") or "?"
            states[state] = states.get(state, 0) + 1
        builds, _ = asc.get_all(f"/betaGroups/{group['id']}/builds", {"fields[builds]": "version", "limit": "200"})
        has = sorted(b["attributes"]["version"] for b in builds if b["id"] in build_ids)
        kind = "internal" if a.get("isInternalGroup") else "external"
        print(f"- {a['name']} ({kind}{', all builds' if a.get('hasAccessToAllBuilds') else ''}): "
              f"{len(testers)} tester(s) " + (", ".join(f"{n} {s}" for s, n in sorted(states.items())) or "")
              + f" · latest builds in it: {', '.join(has) or 'none'}")


if __name__ == "__main__":
    main()
