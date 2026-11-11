"""Check module scope, PR range selection, and diagnostic preservation."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]

STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
files = []
for i in range(int(os.environ.get("SCRIPT_INPUT_FILE_LIST_COUNT", "0"))):
    files += pathlib.Path(os.environ[f"SCRIPT_INPUT_FILE_LIST_{i}"]).read_text().splitlines()
for i in range(int(os.environ.get("SCRIPT_INPUT_FILE_COUNT", "0"))):
    files.append(os.environ[f"SCRIPT_INPUT_FILE_{i}"])
fd = os.open(os.environ["TEST_ANALYZER_LOG"], os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
os.write(fd, (json.dumps({"args": args, "files": files}) + "\n").encode())
os.close(fd)
if "--output" in args:
    if os.environ.get("TEST_NO_REPORT") == "1":
        sys.exit(2)
    count = int(os.environ.get("TEST_FINDINGS", "0"))
    findings = [{"file": "rankbuddy-macos/First.swift", "line": i + 1, "character": 1,
                 "severity": "error", "reason": "an analyzer finding", "rule_id": "unused_declaration"}
                for i in range(count)]
    pathlib.Path(args[args.index("--output") + 1]).write_text(json.dumps(findings))
    sys.exit(2 if count else 0)
'''


class AnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        self.script = self.root / "scripts/run-swiftlint-analyzer.sh"
        shutil.copy2(REPO / "scripts/run-swiftlint-analyzer.sh", self.script)
        self.sources = {"rankbuddy-macos/First.swift", "rankbuddy-macos/Views/Other View.swift"}
        for name in self.sources | {"rankbuddy-macosTests/Test.swift"}:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// initial\n")
        (self.root / ".swiftlint.yml").write_text("included:\n  - rankbuddy-macos\n  - rankbuddy-macosTests\n")
        (self.root / ".swiftlint-analyzer-baseline.json").write_text("[]")
        (self.root / "compiler.log").touch()
        self.tool = self.root / "fake-swiftlint"
        self.tool.write_text(STUB)
        self.tool.chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.git("init", "-q")
        self.commit("initial")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.env = os.environ.copy()
        for name in ("SWIFTLINT_ANALYZE_ALL_IMPORTS", "SWIFTLINT_ANALYZER_DIFF_BASE", "SWIFTLINT_ANALYZER_JOBS"):
            self.env.pop(name, None)
        self.env.update(SWIFTLINT_BIN=str(self.tool), TEST_ANALYZER_LOG=str(self.log))

    def git(self, *args):
        return subprocess.check_output(["git", "-c", "commit.gpgsign=false", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def run_analyzer(self, **environment):
        self.log.unlink(missing_ok=True)
        return subprocess.run([str(self.script), "compiler.log"], cwd=self.root,
                              env=self.env | environment, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_full_pr_range_and_exact_file_scopes(self):
        for i, name in enumerate(sorted(self.sources)):
            (self.root / name).write_text(f"// changed {i}\n")
            self.commit(f"change {i}")
        result = self.run_analyzer(SWIFTLINT_ANALYZER_DIFF_BASE=self.base)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(len(calls), 3)
        self.assertIn("--use-script-input-file-lists", calls[0]["args"])
        expected = {str(self.root / name) for name in self.sources}
        self.assertEqual(set(calls[0]["files"]), expected)
        self.assertEqual(len(calls[0]["files"]), len(expected))
        imports = calls[1:]
        self.assertEqual({call["files"][0] for call in imports}, expected)
        for call in imports:
            self.assertEqual(len(call["files"]), 1)
            self.assertIn("--use-script-input-files", call["args"])
            self.assertIn("unused_import", call["args"])

    def test_non_swift_changes_do_not_repeat_module_scope_for_imports(self):
        (self.root / "README.md").write_text("Documentation\n")
        self.commit("docs")
        self.assertEqual(self.run_analyzer(SWIFTLINT_ANALYZER_DIFF_BASE=self.base).returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_full_import_audit_includes_unchanged_shipping_files(self):
        result = self.run_analyzer(SWIFTLINT_ANALYZE_ALL_IMPORTS="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({call["files"][0] for call in self.calls()[1:]},
                         {str(self.root / name) for name in self.sources})

    def test_invalid_base_fails_before_analyzer_runs(self):
        result = self.run_analyzer(SWIFTLINT_ANALYZER_DIFF_BASE="missing-reference")
        self.assertEqual(result.returncode, 64)
        self.assertIn("cannot resolve", result.stderr)
        self.assertFalse(self.log.exists())

    def test_invalid_worker_limits_fail_before_analyzer_runs(self):
        for count in ("", "0", "-1", "65", "many"):
            with self.subTest(count=count):
                result = self.run_analyzer(SWIFTLINT_ANALYZER_JOBS=count)
                self.assertEqual(result.returncode, 64)
                self.assertFalse(self.log.exists())

    def test_every_finding_and_failure_status_is_preserved(self):
        result = self.run_analyzer(TEST_FINDINGS="12")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(sum(line.startswith("rankbuddy-macos/First.swift:") for line in result.stdout.splitlines()), 12)
        self.assertEqual(len(self.calls()), 1)

    def test_a_failed_analyzer_cannot_reuse_a_stale_report(self):
        report = self.root / "swiftlint-analyzer-findings.json"
        report.write_text("stale report")
        result = self.run_analyzer(TEST_NO_REPORT="1")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("stale report", result.stdout)
        self.assertFalse(report.exists())


if __name__ == "__main__":
    unittest.main()
