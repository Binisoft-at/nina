#!/usr/bin/env python3
"""Adds a platform (macOS, iOS) to this app's App Store Connect record, the way "Add Platform" does
on the website: it creates the platform's first App Store version (MARKETING_VERSION). Changes the
team's App Store Connect – run it only with the owner's OK (HOW_WE_WORK section 4).

A record without MAC_OS can't take Mac uploads. (A brand-new record that has MAC_OS can still fail
its first Mac upload with "Error Downloading App Information" – then just run TestFlight again.)

usage: asc-platform.py macos|ios
env:   ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 (or ASC_KEY_PATH); BUNDLE_ID and VERSION (defaults:
       APP_BUNDLE_ID and MARKETING_VERSION from Config/Base.xcconfig). Synced from the Binisoft handbook.
"""
import os
import subprocess
import sys

import asc

here = os.path.dirname(os.path.abspath(__file__))
PLATFORMS = {"macos": "MAC_OS", "ios": "IOS"}


def setting(name, env):
    if os.environ.get(env):
        return os.environ[env]
    out = subprocess.run([sys.executable, os.path.join(here, "xcconfig.py"), name],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in PLATFORMS:
        sys.exit(__doc__)
    if not asc.has_key():
        sys.exit("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 are needed (repository secrets).")
    platform = PLATFORMS[sys.argv[1]]
    bundle = setting("APP_BUNDLE_ID", "BUNDLE_ID")
    app = asc.find_app(bundle)
    if not app:
        sys.exit(f"No App Store Connect app with bundle ID {bundle}. Create it first (SETUP_CHECKLIST.md, 3.2).")
    print(f"App: {app['attributes']['name']} ({bundle}), id {app['id']}")
    before = asc.platforms(app["id"])
    print("Platforms before: " + (", ".join(sorted(before)) or "none"))
    if platform in before:
        print(f"{platform} is already on the record – nothing to do.")
        return
    version = setting("MARKETING_VERSION", "VERSION")
    asc.request("POST", "/appStoreVersions", body={"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": platform, "versionString": version},
        "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}},
    }})
    after = asc.platforms(app["id"])
    print(f"Added {platform} (App Store version {version}).")
    print("Platforms now: " + ", ".join(sorted(after)))
    if platform not in after:
        sys.exit(f"{platform} still missing – add it on the website (the + next to the platform name).")


if __name__ == "__main__":
    main()
