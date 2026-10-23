"""Exercise packaged cleanup through the real dispatcher using disposable projects."""

import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class BuildArtifactDispatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="jobs-flutter-clean-dispatch-")
        self.base = pathlib.Path(self.temporary.name).resolve()
        self.project = self.base / "工程 [space] ' $(touch SHOULD_NOT_EXIST)\n第二行"
        self.home = self.base / "home"
        self.tools = self.base / "独立资源 Tools"
        self.home.mkdir()
        self.tools.mkdir()
        for name in ["DispatchFlutterTools.zsh", "CleanBuildArtifacts.zsh"]:
            shutil.copy2(ROOT / "Scripts/Tools" / name, self.tools / name)
        self.write("pubspec.yaml", "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
        self.write("lib/main.dart", "void main() {}\n")
        fake_bin = self.base / "bin"
        fake_bin.mkdir()
        for name in ["flutter", "fvm", "dart"]:
            executable = fake_bin / name
            executable.write_text('#!/bin/zsh\n/usr/bin/touch "$HOME/SDK_WAS_CALLED"\nexit 91\n')
            executable.chmod(0o755)
        self.environment = dict(os.environ, HOME=str(self.home), PATH=f"{fake_bin}:/usr/bin:/bin")

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, relative, value="preserve"):
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def dispatch(self, answer="\n", action="clean-build-artifacts", project=None):
        return subprocess.run(
            ["/bin/zsh", str(self.tools / "DispatchFlutterTools.zsh"), action, str(project or self.project)],
            input=answer,
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=15,
        )

    def assert_no_sdk_calls(self):
        self.assertFalse((self.home / "SDK_WAS_CALLED").exists())
        self.assertFalse((self.project / ".fvmrc").exists())
        self.assertFalse((self.project / ".fvm").exists())
        self.assertFalse((self.project / "SHOULD_NOT_EXIST").exists())

    def test_cancel_and_eof_keep_project_without_fvm(self):
        artifact = self.write("build/artifact")
        for answer in ["\n", "no\n", ""]:
            with self.subTest(answer=answer):
                result = self.dispatch(answer)
                self.assertEqual(result.returncode, 1 if answer == "" else 0, result.stdout + result.stderr)
                self.assertIn("工程类型：Flutter", result.stdout)
                self.assertTrue(artifact.exists())
                self.assert_no_sdk_calls()

    def test_block_flow_and_quoted_flutter_declarations_work_without_fvm(self):
        manifests = {
            "plain block": "dependencies:\n  flutter:\n    sdk: flutter\n",
            "inline dependencies": "dependencies: { flutter: { sdk: flutter } }\n",
            "inline flutter": "dependencies:\n  flutter: { sdk: flutter }\n",
            "single quotes": "'dependencies':\n  'flutter':\n    'sdk': 'flutter' # dependency declaration\n",
            "double quotes and flow": '"dependencies": { "flutter": { "sdk": "flutter" }, http: "^1.0.0" } # comment\n',
            "JSON escaped key": '"\\u0064ependencies": { flutter: { sdk: "\\u0066lutter" } }\n',
            "quoted punctuation": "dependencies: { flutter: { sdk: 'flutter', note: 'literal #, : and ''quote''' }, http: '^1.0.0' }\n",
            "BOM and CRLF": "\ufeffdependencies:\r\n  flutter:\r\n    sdk: flutter\r\n",
        }
        artifact = self.write("build/keep")
        for label, manifest in manifests.items():
            with self.subTest(label=label):
                self.write("pubspec.yaml", manifest)
                result = self.dispatch()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("工程类型：Flutter", result.stdout)
                self.assertTrue(artifact.exists())
                self.assert_no_sdk_calls()

    def test_misleading_and_duplicate_yaml_declarations_are_rejected(self):
        manifests = {
            "environment sdk": "environment:\n  sdk: flutter\n",
            "dev dependency": "dependencies: { http: '^1.0.0' }\ndev_dependencies:\n  flutter:\n    sdk: flutter\n",
            "description text": "description: |\n  dependencies:\n    flutter:\n      sdk: flutter\ndependencies: { http: '^1.0.0' }\n",
            "other dependency": "dependencies:\n  other:\n    sdk: flutter\n",
            "duplicate dependencies": "dependencies: { flutter: { sdk: flutter } }\ndependencies: {}\n",
            "duplicate block flutter": "dependencies:\n  flutter: { sdk: flutter }\n  flutter: { sdk: dart }\n",
            "duplicate block sdk": "dependencies:\n  flutter:\n    sdk: flutter\n    sdk: dart\n",
            "duplicate flow flutter": "dependencies: { flutter: { sdk: flutter }, flutter: { sdk: dart } }\n",
            "duplicate flow sdk": "dependencies: { flutter: { sdk: flutter, sdk: dart } }\n",
            "tab indent": "dependencies:\n\tflutter:\n\t  sdk: flutter\n",
            "YAML document boundary": "---\ndependencies: { flutter: { sdk: flutter } }\n",
            "comment only": "# dependencies: { flutter: { sdk: flutter } }\n",
            "unterminated scalar": 'dependencies: { flutter: { sdk: "flutter } }\n',
        }
        artifact = self.write("build/keep")
        for label, manifest in manifests.items():
            with self.subTest(label=label):
                self.write("pubspec.yaml", manifest)
                result = self.dispatch("CLEAN\n")
                self.assertNotEqual(result.returncode, 0, label)
                self.assertTrue(artifact.exists())
                self.assert_no_sdk_calls()

    def test_project_without_lib_accepts_flow_and_quoted_dependencies(self):
        shutil.rmtree(self.project / "lib")
        artifact = self.write("build/keep")
        for manifest in [
            "dependencies: { flutter: { sdk: flutter } }\n",
            "'dependencies':\n  'flutter':\n    'sdk': 'flutter'\n",
            '"dependencies": { "flutter": { "sdk": "flutter" } }\n',
        ]:
            with self.subTest(manifest=manifest):
                self.write("pubspec.yaml", manifest)
                result = self.dispatch()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("工程类型：Flutter", result.stdout)
                self.assertTrue(artifact.exists())
                self.assertFalse((self.project / "lib").exists())
                self.assert_no_sdk_calls()

    def test_oversized_invalid_utf8_and_linked_manifests_are_rejected(self):
        artifact = self.write("build/keep")
        manifest = self.project / "pubspec.yaml"
        valid = b"dependencies: { flutter: { sdk: flutter } }\n"
        for content in [valid + b"#" + b"x" * 1_048_576, valid + b"#\xff\n"]:
            with self.subTest(content_size=len(content)):
                manifest.write_bytes(content)
                result = self.dispatch("CLEAN\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(artifact.exists())
                self.assert_no_sdk_calls()
        external = self.base / "external-pubspec.yaml"
        external.write_bytes(valid)
        manifest.unlink()
        manifest.symlink_to(external)
        result = self.dispatch("CLEAN\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(artifact.exists())
        self.assertEqual(external.read_bytes(), valid)
        self.assert_no_sdk_calls()

    def test_packaged_cleaner_keeps_native_platform_scope_and_protected_files(self):
        self.write("android/settings.gradle.kts", 'include(":app")')
        self.write("android/app/build.gradle.kts", 'plugins { id("com.android.application") }')
        self.write("ios/Demo.xcodeproj/project.pbxproj", "SDKROOT = iphoneos;")
        for relative in ["ohos/hvigorfile.ts", "ohos/build-profile.json5", "ohos/oh-package.json5", "ohos/AppScope/app.json5", "ohos/entry/build-profile.json5", "ohos/entry/src/main/module.json5"]:
            self.write(relative, "{}")
        outputs = ["build", ".dart_tool", "android/build", "android/.gradle", "android/.kotlin", "android/app/build", "android/app/.cxx", "android/app/.externalNativeBuild", "ios/build", "ios/DerivedData", "ios/Flutter/ephemeral", "ohos/build", "ohos/.hvigor", "ohos/entry/build", "ohos/entry/.hvigor", "windows/flutter/ephemeral", "linux/flutter/ephemeral", "macos/Flutter/ephemeral"]
        for relative in outputs:
            self.write(f"{relative}/artifact")
        protected = ["lib/main.dart", "pubspec.yaml", "pubspec.lock", "ios/Podfile.lock", "ios/Pods/source", "ios/Flutter/Generated.xcconfig", "android/local.properties", "ohos/entry/libs/flutter.har", "ohos/oh_modules/dependency/build/keep", "unrelated/build/keep"]
        for relative in protected[2:]:
            self.write(relative)
        derived = self.home / "Library/Developer/Xcode/DerivedData"
        own = derived / "Own"
        unrelated = derived / "Other/Build/keep"
        (own / "Build").mkdir(parents=True)
        (own / "Build/artifact").write_text("generated")
        (own / "info.plist").write_bytes(plistlib.dumps({"WorkspacePath": str(self.project / "ios/Demo.xcodeproj")}))
        unrelated.parent.mkdir(parents=True)
        unrelated.write_text("preserve")
        shared = self.home / ".gradle/caches/keep"
        shared.parent.mkdir(parents=True)
        shared.write_text("shared")
        result = self.dispatch("CLEAN\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for relative in outputs:
            self.assertFalse((self.project / relative).exists(), relative)
        for relative in protected:
            self.assertTrue((self.project / relative).exists(), relative)
        self.assertFalse((own / "Build").exists())
        self.assertTrue((own / "info.plist").exists())
        self.assertTrue(unrelated.exists())
        self.assertTrue(shared.exists())
        self.assert_no_sdk_calls()
        result = self.dispatch("CLEAN\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("没有可清理的构建产物", result.stdout)

    def test_non_flutter_root_is_rejected_before_cleanup(self):
        artifact = self.write("build/keep")
        self.write("settings.gradle.kts", 'include(":app")')
        self.write("app/build.gradle.kts", 'plugins { id("com.android.application") }')
        self.write("pubspec.yaml", "name: ordinary_dart\n")
        result = self.dispatch("CLEAN\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("请选择合法 Flutter 项目根目录", result.stderr)
        self.assertTrue(artifact.exists())
        self.assert_no_sdk_calls()

    def test_linked_target_rejects_entire_plan_before_deleting(self):
        artifact = self.write("build/keep")
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "keep").write_text("preserve")
        (self.project / ".dart_tool").symlink_to(outside)
        result = self.dispatch("CLEAN\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(artifact.exists())
        self.assertTrue((outside / "keep").exists())
        self.assert_no_sdk_calls()

    def test_linked_project_is_rejected_before_canonicalization(self):
        artifact = self.write("build/keep")
        link = self.base / "project-link"
        link.symlink_to(self.project)
        result = self.dispatch("CLEAN\n", project=link)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("不能是符号链接", result.stderr)
        self.assertTrue(artifact.exists())
        self.assert_no_sdk_calls()

    def test_sdk_maintenance_keeps_fvm_requirement(self):
        result = self.dispatch("\n", action="maintenance")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("尚未通过 FVM 绑定 SDK", result.stderr)
        self.assert_no_sdk_calls()


if __name__ == "__main__":
    unittest.main(verbosity=2)
