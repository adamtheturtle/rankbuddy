"""Exercise the profile restrictions that previously prevented app launch."""

import copy
from datetime import datetime, timedelta
import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_developer_id_signing import validate_profile


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 11, 8)
        self.team = "EXAMPLETEAM"
        self.bundle = "com.example.app"
        self.certificate = b"synthetic signing certificate"
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest()
        self.requested = {"com.apple.developer.ubiquity-kvstore-identifier": self.team + "." + self.bundle,
                          "com.apple.security.app-sandbox": True}
        self.profile = {"Platform": ["OSX"], "ProvisionsAllDevices": True,
                        "ExpirationDate": self.now + timedelta(days=1), "TeamIdentifier": [self.team],
                        "DeveloperCertificates": [self.certificate],
                        "Entitlements": {"com.apple.application-identifier": self.team + "." + self.bundle,
                                         "com.apple.developer.ubiquity-kvstore-identifier": self.team + ".*"}}

    def validate(self, profile=None, fingerprint=None):
        return validate_profile(profile or self.profile, self.requested, self.bundle, self.team,
                                fingerprint or self.fingerprint, self.now)

    def test_matching_profile_expands_application_and_team_identifiers(self):
        result = self.validate()
        self.assertEqual(result["com.apple.application-identifier"], self.team + "." + self.bundle)
        self.assertEqual(result["com.apple.developer.team-identifier"], self.team)
        self.assertTrue(result["com.apple.security.app-sandbox"])

    def test_development_profile_is_rejected(self):
        self.profile["ProvisionsAllDevices"] = False
        self.profile["ProvisionedDevices"] = ["synthetic-mac"]
        with self.assertRaisesRegex(ValueError, "development profile"):
            self.validate()

    def test_expired_profile_is_rejected(self):
        self.profile["ExpirationDate"] = self.now
        with self.assertRaisesRegex(ValueError, "expired"):
            self.validate()

    def test_wrong_team_is_rejected(self):
        self.profile["TeamIdentifier"] = ["OTHERTEAM"]
        with self.assertRaisesRegex(ValueError, "different team"):
            self.validate()

    def test_wrong_app_is_rejected(self):
        self.profile["Entitlements"]["com.apple.application-identifier"] = self.team + ".com.other.app"
        with self.assertRaisesRegex(ValueError, "application identifier"):
            self.validate()

    def test_wrong_certificate_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "signing certificate"):
            self.validate(fingerprint="0" * 40)

    def test_missing_icloud_permission_is_rejected(self):
        self.profile["Entitlements"].pop("com.apple.developer.ubiquity-kvstore-identifier")
        with self.assertRaisesRegex(ValueError, "ubiquity-kvstore"):
            self.validate()

    def test_debugging_permission_is_rejected(self):
        self.profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaisesRegex(ValueError, "debugging"):
            self.validate()

    def test_does_not_modify_requested_entitlements(self):
        original = copy.deepcopy(self.requested)
        self.validate()
        self.assertEqual(self.requested, original)


if __name__ == "__main__":
    unittest.main()
