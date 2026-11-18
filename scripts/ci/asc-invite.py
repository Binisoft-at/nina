#!/usr/bin/env python3
"""Resends the TestFlight invitation to every tester of this app who hasn't accepted yet (state
INVITED or NOT_INVITED), through the API key – for invitation emails that never arrived. Sends
emails from App Store Connect, so only with the owner's OK (HOW_WE_WORK section 4). Testers are
counted, never named: this output may be public.

env: ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 (or ASC_KEY_PATH); BUNDLE_ID (default: APP_BUNDLE_ID from
     Config/Base.xcconfig). Synced from the Binisoft handbook.
"""
import os
import subprocess
import sys

import asc

here = os.path.dirname(os.path.abspath(__file__))
PENDING = {"INVITED", "NOT_INVITED"}


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
    app = asc.find_app(bundle)
    if not app:
        sys.exit(f"No App Store Connect app with bundle ID {bundle}.")
    print(f"App: {app['attributes']['name']} ({bundle}), id {app['id']}")
    groups, _ = asc.get_all(f"/apps/{app['id']}/betaGroups", {"fields[betaGroups]": "name", "limit": "50"})
    pending = {}
    for group in groups:
        testers, _ = asc.get_all(f"/betaGroups/{group['id']}/betaTesters", {"fields[betaTesters]": "state", "limit": "200"})
        for tester in testers:
            if (tester["attributes"].get("state") or "") in PENDING:
                pending[tester["id"]] = group["attributes"]["name"]
    if not pending:
        print("Every tester has accepted – nothing to resend.")
        return
    sent, failed = 0, 0
    for tester_id, group in pending.items():
        try:
            asc.request("POST", "/betaTesterInvitations", body={"data": {
                "type": "betaTesterInvitations",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app["id"]}},
                    "betaTester": {"data": {"type": "betaTesters", "id": tester_id}},
                },
            }})
            sent += 1
        except RuntimeError as error:
            failed += 1
            print(f"- a tester in {group}: {str(error).split('→')[-1].strip()[:300]}")
    print(f"Invitations resent: {sent}; failed: {failed}.")
    if sent:
        print("They arrive from no_reply@email.apple.com: open on the iPhone → View in TestFlight → Accept.")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
