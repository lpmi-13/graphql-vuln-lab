"""Exercise publishing with fake docker and labctl commands."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
IMAGE = "ghcr.io/example/graphql-rootfs"


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / "playground" / "iximiuz"
        scripts.mkdir(parents=True)
        for name in ("publish.sh", "build-rootfs-image.sh"):
            shutil.copy2(HERE / name, scripts / name)
        (self.root / "index.md").write_text("Test challenge\n")
        self.manifest = scripts / "manifest.yaml"

        mock_bin = self.root / "mock-bin"
        mock_bin.mkdir()
        stub = mock_bin / "stub"
        stub.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, shutil, sys\n"
            "from pathlib import Path\n"
            "name = Path(sys.argv[0]).name\n"
            "args = sys.argv[1:]\n"
            "with open(os.environ['CALL_LOG'], 'a') as log:\n"
            "    log.write(json.dumps([name, *args]) + '\\n')\n"
            "if name == 'labctl' and args[:2] == ['playground', 'update']:\n"
            "    shutil.copy2(args[args.index('-f') + 1], os.environ['CAPTURE_MANIFEST'])\n"
            "if os.environ.get('FAIL_AT') == name + ' ' + args[0]:\n"
            "    sys.exit(1)\n"
        )
        stub.chmod(0o755)
        (mock_bin / "docker").symlink_to(stub)
        (mock_bin / "labctl").symlink_to(stub)
        self.log = self.root / "calls.jsonl"
        self.capture = self.root / "sent-manifest.yaml"
        self.env = os.environ | {
            "PATH": f"{mock_bin}:{os.environ['PATH']}",
            "CALL_LOG": str(self.log),
            "CAPTURE_MANIFEST": str(self.capture),
        }

    def publish(self, current_version, fail_at=None):
        self.log.write_text("")
        self.manifest.write_text(
            "kind: playground\n"
            "playground:\n"
            "  machines:\n"
            "    - drives:\n"
            f"        - source: oci://{IMAGE}:v{current_version}\n"
            "          mount: /\n"
        )
        env = self.env | ({"FAIL_AT": fail_at} if fail_at else {})
        result = subprocess.run(
            ["bash", str(self.root / "playground" / "iximiuz" / "publish.sh")],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def test_multi_digit_versions(self):
        for current, next_version in ((9, 10), (10, 11), (99, 100)):
            with self.subTest(current=current):
                result, calls = self.publish(current)
                self.assertEqual(result.returncode, 0, result.stderr)
                next_image = f"{IMAGE}:v{next_version}"
                self.assertIn(f"oci://{next_image}", self.manifest.read_text())
                self.assertIn(f"oci://{next_image}", self.capture.read_text())
                self.assertTrue(
                    any(call[:2] == ["docker", "build"] and next_image in call for call in calls)
                )
                self.assertIn(["docker", "push", next_image], calls)
                push = calls.index(["docker", "push", next_image])
                playground = next(
                    i for i, call in enumerate(calls)
                    if call[:3] == ["labctl", "playground", "update"]
                )
                content = next(
                    i for i, call in enumerate(calls)
                    if call[:3] == ["labctl", "content", "push"]
                )
                self.assertLess(push, playground)
                self.assertLess(playground, content)

    def test_failed_push_does_not_advance_manifest(self):
        result, calls = self.publish(10, fail_at="docker push")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"oci://{IMAGE}:v10", self.manifest.read_text())
        self.assertFalse(any(call[:3] == ["labctl", "playground", "update"] for call in calls))

    def test_failed_playground_update_does_not_advance_manifest(self):
        result, _ = self.publish(10, fail_at="labctl playground")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"oci://{IMAGE}:v10", self.manifest.read_text())


if __name__ == "__main__":
    unittest.main()
