"""Exercise package import repair through packaged resources and disposable projects."""

import errno
import os
import pathlib
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS = ROOT / "Scripts/Tools"
SOURCE_NAME = "【MacOS】⚙️import =＞package💣.command"
SOURCE = ROOT.parents[2] / "JobsCommand@Flutter/MacOS/小工具" / SOURCE_NAME / SOURCE_NAME


class PackageImportDispatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="jobs-package-import-dispatch-")
        self.base = pathlib.Path(self.temporary.name).resolve()
        self.project = self.base / "中文 工程 [space] ' \" ; $(touch SHELL_INJECTION)\n第二行"
        self.home = self.base / "home"
        self.tools = self.base / "独立资源 Tools"
        self.runtime = self.base / "runtime"
        for directory in [self.home, self.tools, self.runtime]:
            directory.mkdir()
        for name in ["DispatchFlutterTools.zsh", "CleanBuildArtifacts.zsh", "RepairPackageImports.zsh"]:
            shutil.copy2(TOOLS / name, self.tools / name)
        self.write("pubspec.yaml", "name: fixture_app\ndependencies:\n  flutter:\n    sdk: flutter\n")
        self.write("lib/main.dart", "void main() {}\n")
        fake_bin = self.base / "bin"
        fake_bin.mkdir()
        for name in ["flutter", "fvm", "dart", "brew", "curl", "git"]:
            executable = fake_bin / name
            executable.write_text('#!/bin/zsh\n/usr/bin/touch "$HOME/EXTERNAL_TOOL_WAS_CALLED"\nexit 91\n')
            executable.chmod(0o755)
        self.environment = dict(
            os.environ,
            HOME=str(self.home),
            TMPDIR=str(self.runtime) + "/",
            PATH=f"{fake_bin}:/usr/bin:/bin",
            NO_COLOR="1",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, relative, value):
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def run_script(self, arguments, answer="", script="RepairPackageImports.zsh", terminal=False):
        command = ["/bin/zsh", str(self.tools / script), *map(str, arguments)]
        if terminal:
            return self.run_in_terminal(command, answer)
        return subprocess.run(
            command,
            input=answer,
            env=self.environment,
            cwd=self.base,
            capture_output=True,
            text=True,
            timeout=20,
        )

    def run_in_terminal(self, command, answer):
        master, slave = pty.openpty()
        process = None
        output = bytearray()
        deadline = time.monotonic() + 20
        try:
            process = subprocess.Popen(
                command,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                env=self.environment,
                cwd=self.base,
                close_fds=True,
            )
            os.close(slave)
            slave = None
            # Canonical-mode EOF lets cancellation tests close input without losing captured output.
            os.write(master, answer.encode("utf-8") + b"\x04")
            while time.monotonic() < deadline:
                if not select.select([master], [], [], 0.1)[0]:
                    if process.poll() is not None:
                        break
                    continue
                try:
                    data = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                output.extend(data)
            process.wait(timeout=max(0.1, deadline - time.monotonic()))
            return subprocess.CompletedProcess(command, process.returncode, output.decode("utf-8", "replace"), "")
        finally:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            if slave is not None:
                os.close(slave)

    def dispatch(self, answer="\nYES\n", project=None):
        return self.run_script(
            ["repair-package-imports", project if project is not None else self.project],
            answer,
            script="DispatchFlutterTools.zsh",
            terminal=True,
        )

    def assert_succeeded(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_no_external_tools()

    def assert_no_external_tools(self):
        self.assertFalse((self.home / "EXTERNAL_TOOL_WAS_CALLED").exists())
        self.assertFalse((self.project / ".fvmrc").exists())
        self.assertFalse((self.project / ".fvm").exists())
        self.assertFalse((self.project / "SHELL_INJECTION").exists())
        self.assertFalse((self.base / "SHELL_INJECTION").exists())

    def snapshot(self):
        return {
            str(path.relative_to(self.project)): ("link", os.readlink(path))
            if path.is_symlink()
            else ("file", path.read_bytes())
            for path in self.project.rglob("*")
            if path.is_file() or path.is_symlink()
        }

    def test_packaged_resource_matches_standalone_source(self):
        if not SOURCE.is_file():
            self.skipTest("Sibling JobsCommand@Flutter checkout is unavailable")
        self.assertEqual((TOOLS / "RepairPackageImports.zsh").read_bytes(), SOURCE.read_bytes())

    def test_option_like_project_names_cannot_bypass_terminal_confirmation(self):
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        for name in ["--check", "--dry-run", "--help", "-h"]:
            with self.subTest(name=name):
                project = self.base / name
                shutil.copytree(self.project, project)
                result = self.run_script(["--project", name], "\nYES\n")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((project / "lib/main.dart").read_text(), "import 'target.dart';\n")
                self.assertEqual(list(self.runtime.iterdir()), [])
                self.assert_no_external_tools()

    def test_dispatch_resolves_imports_from_each_file_without_sdk(self):
        self.write("lib/models/person.dart", "class Person {}\n")
        self.write("lib/models/user.dart", "import 'person.dart';\n")
        main = self.write("lib/main.dart", "import './models/user.dart';\nvoid main() {}\n")
        self.assert_succeeded(self.dispatch())
        self.assertEqual(main.read_text(), "import 'package:fixture_app/models/user.dart';\nvoid main() {}\n")
        self.assertEqual(
            (self.project / "lib/models/user.dart").read_text(),
            "import 'package:fixture_app/models/person.dart';\n",
        )

    def test_legal_flutter_manifests_supported_by_the_menu_can_be_repaired(self):
        self.write("lib/target.dart", "class Target {}\n")
        manifests = [
            "name: fixture_app\ndependencies: { flutter: { sdk: flutter } }\n",
            "name: 'fixture_app'\n'dependencies':\n  'flutter':\n    'sdk': 'flutter'\n",
            'name: "fixture_app"\n"dependencies": { "flutter": { "sdk": "flutter" } }\n',
            "\ufeffname: fixture_app\r\ndependencies:\r\n  flutter:\r\n    sdk: flutter\r\n",
        ]
        for manifest in manifests:
            with self.subTest(manifest=manifest):
                self.write("pubspec.yaml", manifest)
                source = self.write("lib/main.dart", "import 'target.dart';\n")
                self.assert_succeeded(self.dispatch())
                self.assertEqual(source.read_text(), "import 'package:fixture_app/target.dart';\n")

    def test_test_and_nested_imports_are_resolved_from_their_own_directory(self):
        self.write("lib/models/user.dart", "class User {}\n")
        tests = self.write("test/main_test.dart", "import '../lib/models/user.dart';\n")
        nested = self.write("lib/pages/nested/page.dart", "import '../../models/user.dart';\n")
        self.assert_succeeded(self.dispatch())
        expected = "import 'package:fixture_app/models/user.dart';\n"
        self.assertEqual(tests.read_text(), expected)
        self.assertEqual(nested.read_text(), expected)

    def test_conditional_imports_preserve_conditions_and_suffixes(self):
        for name in ["base", "io", "web"]:
            self.write(f"lib/platform/{name}.dart", "void platform() {}\n")
        main = self.write(
            "lib/main.dart",
            "import 'platform/base.dart'\n"
            "    if (dart.library.io == 'platform/io.dart') 'platform/io.dart'\n"
            '    if (dart.library.html) "platform/web.dart" as platform show platform;\n',
        )
        self.assert_succeeded(self.dispatch())
        self.assertEqual(
            main.read_text(),
            "import 'package:fixture_app/platform/base.dart'\n"
            "    if (dart.library.io == 'platform/io.dart') 'package:fixture_app/platform/io.dart'\n"
            '    if (dart.library.html) "package:fixture_app/platform/web.dart" as platform show platform;\n',
        )

    def test_package_dart_export_part_comments_and_strings_are_preserved(self):
        self.write("lib/target.dart", "class Target {}\n")
        content = (
            "import 'package:fixture_app/target.dart';\n"
            "import 'package:other/target.dart';\n"
            "import 'dart:async';\n"
            "export 'target.dart';\n"
            "part 'target.dart';\n"
            "// import 'target.dart';\n"
            "/* import 'target.dart'; */\n"
            'const text = "import \'target.dart\';";\n'
            "const multiline = '''\nimport 'target.dart';\n''';\n"
        )
        main = self.write("lib/main.dart", content)
        self.assert_succeeded(self.dispatch())
        self.assertEqual(main.read_text(), content)

    def test_missing_and_outside_lib_targets_are_preserved(self):
        self.write("outside.dart", "class Outside {}\n")
        (self.base / "outside.dart").write_text("class External {}\n")
        content = (
            "import '../missing.dart';\n"
            "import '../../outside.dart';\n"
            "import '../../../outside.dart';\n"
            "import 'https://example.invalid/remote.dart';\n"
            "import '/absolute.dart';\n"
        )
        source = self.write("lib/pages/page.dart", content)
        self.assert_succeeded(self.dispatch())
        self.assertEqual(source.read_text(), content)

    def test_generated_third_party_and_other_authors_are_preserved(self):
        self.write("lib/target.dart", "class Target {}\n")
        protected = {
            "lib/main.g.dart": "import 'target.dart';\n",
            "lib/main.freezed.dart": "import 'target.dart';\n",
            "lib/generated.dart": "// GENERATED CODE - DO NOT MODIFY BY HAND\nimport 'target.dart';\n",
            "lib/another_author.dart": "// Created by Someone Else on 2026/10/23.\nimport 'target.dart';\n",
            "lib/vendor/source.dart": "import '../target.dart';\n",
            "lib/third_party/source.dart": "import '../target.dart';\n",
            "Pods/source.dart": "import '../lib/target.dart';\n",
            ".dart_tool/source.dart": "import '../lib/target.dart';\n",
            "node_modules/source.dart": "import '../lib/target.dart';\n",
            "build/source.dart": "import '../lib/target.dart';\n",
        }
        for name, content in protected.items():
            self.write(name, content)
        owned = self.write("lib/owned.dart", "// Created by Jobs on 2026/10/23.\nimport 'target.dart';\n")
        self.assert_succeeded(self.dispatch())
        for name, content in protected.items():
            self.assertEqual((self.project / name).read_text(), content, name)
        self.assertIn("import 'package:fixture_app/target.dart';", owned.read_text())

    def test_linked_files_directories_and_targets_are_preserved(self):
        external = self.base / "outside"
        external.mkdir()
        external_source = external / "external.dart"
        original = "import '../lib/main.dart';\n"
        external_source.write_text(original)
        (self.project / "lib/linked.dart").symlink_to(external_source)
        (self.project / "lib/linked_directory").symlink_to(external)
        target = self.write("lib/target.dart", "class Target {}\n")
        (self.project / "lib/alias.dart").symlink_to(target)
        source = self.write("lib/use_link.dart", "import 'alias.dart';\nimport 'linked_directory/external.dart';\n")
        self.assert_succeeded(self.dispatch())
        self.assertEqual(external_source.read_text(), original)
        self.assertEqual(source.read_text(), "import 'alias.dart';\nimport 'linked_directory/external.dart';\n")
        self.assertTrue((self.project / "lib/linked.dart").is_symlink())
        self.assertTrue((self.project / "lib/alias.dart").is_symlink())

    def test_cancel_and_eof_leave_project_unchanged(self):
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        before = self.snapshot()
        for answer in ["", "no\n", "\n", "\nno\n", "\nyes\n", "\n YES\n"]:
            with self.subTest(answer=answer):
                result = self.dispatch(answer)
                self.assertEqual(self.snapshot(), before, result.stdout + result.stderr)
                self.assert_no_external_tools()

    def test_check_and_dry_run_are_noninteractive_and_leave_no_artifacts(self):
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        before = self.snapshot()
        for option in ["--check", "--dry-run"]:
            with self.subTest(option=option):
                self.assert_succeeded(self.run_script(["--project", self.project, option]))
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(list(self.runtime.iterdir()), [])

    def test_piped_confirmation_cannot_bypass_terminal_requirement(self):
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        before = self.snapshot()
        result = self.run_script(["--project", self.project], "\nYES\n")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assert_no_external_tools()

    def test_success_creates_exact_original_backup_and_a_log_outside_project(self):
        self.write("lib/target.dart", "class Target {}\n")
        original = b"import 'target.dart';\r\nvoid main() {}\r\n"
        main = self.project / "lib/main.dart"
        main.write_bytes(original)
        self.assert_succeeded(self.dispatch())
        sessions = list(self.runtime.glob("jobs-flutter-imports.*"))
        self.assertEqual(len(sessions), 1)
        self.assertEqual((sessions[0] / "backup/lib/main.dart").read_bytes(), original)
        self.assertTrue((sessions[0] / "imports.log").is_file())
        self.assertEqual(main.read_bytes(), b"import 'package:fixture_app/target.dart';\r\nvoid main() {}\r\n")
        self.assertEqual(
            {str(path.relative_to(self.project)) for path in self.project.rglob("*") if path.is_file()},
            {"pubspec.yaml", "lib/main.dart", "lib/target.dart"},
        )

    def test_ordinary_dart_parent_and_platform_directories_are_rejected(self):
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        platform = self.project / "android"
        platform.mkdir()
        before = self.snapshot()
        for target in [self.base, platform]:
            with self.subTest(target=str(target)):
                result = self.dispatch(project=target)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.snapshot(), before)
                self.assert_no_external_tools()
        self.write("pubspec.yaml", "name: ordinary_dart\ndependencies: {}\n")
        before = self.snapshot()
        result = self.dispatch()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assert_no_external_tools()

    def test_direct_check_rejects_dev_dependency_only_projects(self):
        self.write(
            "pubspec.yaml",
            "name: fixture_app\ndependencies: {}\ndev_dependencies:\n  flutter:\n    sdk: flutter\n",
        )
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        before = self.snapshot()
        result = self.run_script(["--project", self.project, "--check"])
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(list(self.runtime.iterdir()), [])
        self.assert_no_external_tools()

    def test_symbolic_link_project_is_rejected_before_canonicalization(self):
        alias = self.base / "project-alias"
        alias.symlink_to(self.project)
        before = self.snapshot()
        result = self.dispatch(project=alias)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assert_no_external_tools()

    def test_repeated_execution_is_idempotent(self):
        self.write("lib/target.dart", "class Target {}\n")
        self.write("lib/main.dart", "import 'target.dart';\n")
        self.assert_succeeded(self.dispatch())
        before = self.snapshot()
        self.assert_succeeded(self.dispatch())
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
