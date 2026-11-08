#!/usr/bin/env python3
"""Validate and embed the Developer ID profile before signing the app."""

import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import subprocess


def validate_profile(profile, requested, bundle_id, team_id, identity_hash, now=None):
    """Reject profiles that cannot authorize this Developer ID application."""
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)
    if "OSX" not in profile.get("Platform", []):
        raise ValueError("The provisioning profile is not for macOS")
    if not profile.get("ProvisionsAllDevices") or profile.get("ProvisionedDevices"):
        raise ValueError("Use a Developer ID distribution profile, not a development profile")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("A release profile must not allow debugging")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, datetime) or expiry <= now:
        raise ValueError("The provisioning profile has expired")
    if team_id not in profile.get("TeamIdentifier", []):
        raise ValueError("The profile belongs to a different team")
    expected_id = team_id + "." + bundle_id
    allowed_id = entitlements.get("com.apple.application-identifier", "")
    if not fnmatch.fnmatchcase(expected_id, allowed_id):
        raise ValueError("The profile does not authorize this application identifier")
    hashes = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
    if identity_hash.upper() not in hashes:
        raise ValueError("The profile does not include the selected signing certificate")

    def allows(value, permission):
        if isinstance(value, str) and isinstance(permission, str):
            return fnmatch.fnmatchcase(value, permission)
        if isinstance(value, list) and isinstance(permission, list):
            return all(any(allows(item, allowed) for allowed in permission) for item in value)
        return value == permission

    for key, value in requested.items():
        if key.startswith("com.apple.developer.") and not allows(value, entitlements.get(key)):
            raise ValueError("The profile does not authorize entitlement " + key)
        if key in ("keychain-access-groups", "com.apple.security.application-groups"):
            if key == "com.apple.security.application-groups" and all(
                group.startswith(team_id + ".group.") for group in value
            ):
                continue
            if not allows(value, entitlements.get(key)):
                raise ValueError("The profile does not authorize entitlement " + key)
    result = dict(requested)
    result["com.apple.application-identifier"] = expected_id
    result["com.apple.developer.team-identifier"] = team_id
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--entitlements", type=Path, required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--identity", required=True)
    args = parser.parse_args()
    profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(args.profile)]))
    with (args.app / "Contents/Info.plist").open("rb") as stream:
        bundle_id = plistlib.load(stream)["CFBundleIdentifier"]
    with args.entitlements.open("rb") as stream:
        requested = plistlib.load(stream)
    identity_hash = args.identity
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", identity_hash):
        identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
        matches = [fingerprint for fingerprint, name in re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
                   if name == args.identity]
        if len(matches) != 1:
            parser.error("Pass the hash of exactly one Developer ID signing identity")
        identity_hash = matches[0]
    try:
        expanded = validate_profile(profile, requested, bundle_id, args.team, identity_hash)
    except ValueError as error:
        parser.error(str(error))
    with args.entitlements.open("wb") as stream:
        plistlib.dump(expanded, stream)
    shutil.copyfile(args.profile, args.app / "Contents/embedded.provisionprofile")
    print("Validated and embedded the Developer ID profile for " + bundle_id)


if __name__ == "__main__":
    main()
