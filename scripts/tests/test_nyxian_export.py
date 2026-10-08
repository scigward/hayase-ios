"""Portable contract tests for the Nyxian export (no Apple toolchain required)."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SCRIPT_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIRECTORY))
SPEC = importlib.util.spec_from_file_location("nyxian_export", SCRIPT_DIRECTORY / "nyxian_export.py")
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class XcodeFixture:
    """Keep spaces, realistic file lists and both static/dynamic frameworks."""

    def __init__(self, root):
        self.root = root
        self.repo = root / "checkout with spaces"
        self.derived = root / "Derived Data"
        self.packages = root / "Source Packages"
        self.project = root / "stage" / "Hayase"
        self.products = self.derived / "Build/Products/Release-iphoneos"
        self.target_temp = self.derived / "Build/Intermediates.noindex/Hayase.build/Release-iphoneos/Hayase.build"
        self.sdk = root / "iPhoneOS.sdk"
        self.app = self.products / "Hayase.app"
        self.source = self.write(self.repo / "Hayase/Source/App Delegate.swift", "import UIKit\n")
        self.core_source = self.write(self.repo / "CoreDataService/Source/CoreData.swift", "import CoreData\n")
        self.app_object = self.write(self.target_temp / "Objects-normal/arm64/App Delegate.o", "old app object")
        self.package_object = self.write(
            self.derived / "Build/Intermediates.noindex/SwiftSoup.build/Release-iphoneos/SwiftSoup.build/Objects-normal/arm64/SwiftSoup.o",
            "package object",
        )
        self.extra_object = self.write(
            self.derived / "Build/Intermediates.noindex/SwiftSoup.build/Release-iphoneos/SwiftSoup.build/Objects-normal/arm64/Parser.o",
            "another package object",
        )
        self.archive = self.write(self.products / "libAux.a", "auxiliary static library")
        self.source_list = self.write(
            self.target_temp / "Hayase.SwiftFileList",
            self.source.as_posix() + "\n" + self.core_source.as_posix() + "\n",
        )
        self.link_list = self.write(
            self.target_temp / "Hayase.LinkFileList",
            "\n".join(p.as_posix() for p in (self.app_object, self.package_object, self.extra_object)) + "\n",
        )
        self.package = self.packages / "checkouts/Clang Helper"
        self.write(self.repo / "Hayase.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                   json.dumps({"version": 2, "pins": [{"identity": "clang helper", "location": "https://example.com/Clang Helper.git"}]}))
        self.header = self.write(self.package / "include/CThing.h", "void helper(void);\n")
        self.package_source = self.write(self.package / "SourcePackage.swift", "import Foundation\n")
        self.module_map = self.write(
            self.derived / "Build/Intermediates.noindex/ClangHelper.build/module.modulemap",
            'module ClangHelper { header "' + self.header.as_posix() + '" export * }\n',
        )
        self.module = self.products / "SwiftSoup.swiftmodule"
        self.interface = self.write(
            self.module / "arm64-apple-ios.swiftinterface",
            "// swift-interface-format-version: 1.0\n"
            "// swift-module-flags: -target arm64-apple-ios16.0 -module-name SwiftSoup -module-link-name SwiftSoup\n"
            "import Foundation\n",
        )
        self.serialized_module = self.write(self.module / "arm64-apple-ios.swiftmodule", "compiler-specific module")
        self.dynamic = self.framework(self.products / "NodeMobile.framework", "NodeMobile", "dynamic")
        self.static = self.framework(self.products / "StaticKit.framework", "StaticKit", "static")
        self.framework(self.app / "Frameworks/NodeMobile.framework", "NodeMobile", "dynamic")
        (self.sdk / "System/Library/Frameworks/Foundation.framework").mkdir(parents=True)
        self.write(self.sdk / "usr/lib/libz.tbd", "sdk stub is not exported")
        self.write(self.app / "Hayase", "old compiled app")
        self.write(self.app / "_CodeSignature/CodeResources", "signing data")
        self.write(self.app / "embedded.mobileprovision", "profile is not exported")
        self.info = {
            "CFBundleExecutable": "Hayase", "CFBundleIdentifier": "app.hayase",
            "CFBundleVersion": "0", "CFBundleShortVersionString": "6.4.0",
            "UIMainStoryboardFile": "Main", "UILaunchStoryboardName": "LaunchScreen",
            "UIAppFonts": ["Nunito-Variable.ttf"], "UIDeviceFamily": [1, 2],
        }
        self.write(self.app / "Info.plist", plistlib.dumps(self.info))
        for name in EXPORT.RESOURCE_REQUIREMENTS:
            path = self.app / name
            if path.suffix in {".momd", ".storyboardc"}:
                self.write(path / "compiled resource", "compiled by Xcode")
            else:
                self.write(path, "runtime resource")
        self.write(self.app / "SwiftSoup_SwiftSoup.bundle/resource.txt", "package resource")
        self.write(self.app / "Twemoji/flags.json", "{}")
        self.write(self.app / "Nunito-Variable.ttf", "font")
        self.write(self.repo / "Component/Unrelated.swift", "must not be exported")
        self.settings = {
            "TARGET_BUILD_DIR": str(self.products), "FULL_PRODUCT_NAME": "Hayase.app",
            "TARGET_TEMP_DIR": str(self.target_temp), "SDKROOT": str(self.sdk),
            "EXECUTABLE_NAME": "Hayase", "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        }
        swift = [
            "/Applications/Xcode.app/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
            "-module-name", "Hayase", "-filelist", self.source_list.as_posix(),
            "-I", self.products.as_posix(), "-F", self.products.as_posix(),
            "-Xcc", "-fmodule-map-file=" + self.module_map.as_posix(),
            "-Xcc", "-I" + self.header.parent.as_posix(), "-D", "SWIFT_PACKAGE",
        ]
        package_swift = [
            swift[0], "-module-name", "SwiftSoup", self.package_source.as_posix(),
            "-Xcc", "-fmodule-map-file=" + self.module_map.as_posix(),
        ]
        clang = [
            "/Applications/Xcode.app/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang",
            "-target", "arm64-apple-ios16.0", "-F", self.products.as_posix(),
            "-L", self.products.as_posix(), "-filelist", self.link_list.as_posix(),
            "-framework", "NodeMobile", "-framework", "StaticKit", "-framework", "Foundation",
            "-lAux", "-lz", "-ObjC", "-Wl,-rpath,@executable_path/Frameworks",
            "-o", str(self.app / "Hayase"),
        ]
        self.log = "\n".join((
            "SwiftDriver Hayase normal arm64 (in target 'Hayase')",
            "    builtin-SwiftDriver -- " + shlex.join(swift),
            "    " + shlex.join(package_swift),
            "Ld " + str(self.app / "Hayase") + " normal (in target 'Hayase')",
            "    " + shlex.join(clang),
        ))
        self.archive_calls = []
        self.architecture_checks = []
        self.tracked_files = ["include/CThing.h", "SourcePackage.swift"]

    @staticmethod
    def write(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, bytes):
            path.write_bytes(value)
        else:
            path.write_text(value, encoding="utf-8")
        return path

    def framework(self, directory, name, kind):
        self.write(directory / name, kind + " framework arm64 binary")
        self.write(directory / "Headers" / (name + ".h"), "void frameworkFunction(void);\n")
        self.write(directory / "Modules/module.modulemap",
                   'framework module ' + name + ' { umbrella header "' + name + '.h" export * }\n')
        self.write(directory / "Info.plist", plistlib.dumps({"CFBundlePackageType": "FMWK", "CFBundleExecutable": name}))
        return directory

    def run(self, *args, **kwargs):
        args = [str(a) for a in args]
        if args[:2] == ["xcrun", "libtool"]:
            self.archive_calls.append(args)
            self.write(Path(args[args.index("-o") + 1]), "portable arm64 static archive")
            return ""
        if args[:2] == ["xcrun", "lipo"]:
            # -verify_arch consumes all following arguments as architectures;
            # putting the binary last is invalid on Apple's real lipo.
            if len(args) != 5 or args[3:] != ["-verify_arch", "arm64"] or not Path(args[2]).is_file():
                raise AssertionError("Invalid lipo verification command: " + repr(args))
            self.architecture_checks.append(Path(args[2]))
            return ""
        if args[:2] == ["git", "-C"] and args[-2:] == ["ls-files", "-z"]:
            return "\0".join(self.tracked_files) + "\0"
        raise AssertionError("Unexpected subprocess: " + repr(args))

    def exporter(self):
        return EXPORT.Exporter(self.repo, self.derived, self.packages, self.settings, self.log, self.project)

    def export(self):
        exporter = self.exporter()
        info = exporter.sources_and_resources()
        exporter.archive_objects()
        exporter.frameworks_and_link_flags()
        exporter.import_metadata()
        config = exporter.config(info)
        EXPORT.validate_layout(self.project, config, exporter.source_paths)
        return exporter, config


class ExportContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hayase-nyxian-test-")
        self.addCleanup(self.temporary.cleanup)
        self.fixture = XcodeFixture(Path(self.temporary.name))
        self.patcher = patch.object(EXPORT, "run", side_effect=self.fixture.run)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def alias_paths(self):
        # Reproduce macOS /var -> /private/var with a real directory alias,
        # including on Windows where junctions do not require symlink privilege.
        root = self.fixture.root
        alias = root.with_name(root.name + "-alias")
        if os.name == "nt":
            subprocess.run(["cmd", "/c", "mklink", "/J", str(alias), str(root.resolve())],
                           check=True, capture_output=True)
            self.addCleanup(alias.rmdir)  # Remove only the junction, not its target.
        else:
            alias.symlink_to(root.resolve(), target_is_directory=True)
            self.addCleanup(alias.unlink)
        self.assertEqual(alias.resolve(), root.resolve())
        self.assertNotEqual(alias, alias.resolve())
        return lambda path: alias / path.relative_to(root)

    def test_directory_aliases_export_sources_generated_code_and_import_metadata(self):
        alias = self.alias_paths()
        generated = self.fixture.write(self.fixture.target_temp / "DerivedSources/Generated.swift", "import UIKit\n")
        self.fixture.source_list.write_text(self.fixture.source_list.read_text() + generated.as_posix() + "\n")
        settings = dict(self.fixture.settings)
        for key in ("TARGET_BUILD_DIR", "TARGET_TEMP_DIR", "SDKROOT"):
            settings[key] = str(alias(Path(settings[key])))
        binary = self.fixture.app / "Hayase"
        log = self.fixture.log.replace(str(binary), str(alias(binary)))
        exporter = EXPORT.Exporter(alias(self.fixture.repo), alias(self.fixture.derived),
                                   alias(self.fixture.packages), settings, log, alias(self.fixture.project))
        info = exporter.sources_and_resources()
        exporter.archive_objects()
        exporter.frameworks_and_link_flags()
        exporter.import_metadata()
        config = exporter.config(info)
        EXPORT.validate_layout(exporter.project, config, exporter.source_paths)
        for name in ("repo", "derived", "packages", "project", "products", "target_temp", "sdk"):
            self.assertEqual(getattr(exporter, name), getattr(self.fixture, name).resolve())
        self.assertIn(Path("Generated/DerivedSources/Generated.swift"), exporter.source_paths)
        expected = "$(SRCROOT)/Config/Dependencies/SourcePackages/Clang Helper/include/CThing.h"
        self.assertEqual(exporter.portable(self.fixture.header), expected)
        self.assertEqual(exporter.portable(alias(self.fixture.header)), expected)
        self.assertEqual(exporter.portable(alias(self.fixture.sdk / "usr/lib/libz.tbd")),
                         "$(SDKROOT)/usr/lib/libz.tbd")
        archive = self.fixture.root / "aliased-export.zip"
        EXPORT.zip_project(exporter.project, archive)
        with zipfile.ZipFile(archive) as zipped:
            self.assertIn("Hayase/Generated/DerivedSources/Generated.swift", zipped.namelist())

    def test_link_output_matches_physical_path_when_settings_use_alias(self):
        alias = self.alias_paths()
        settings = dict(self.fixture.settings, TARGET_BUILD_DIR=str(alias(self.fixture.products)))
        binary = self.fixture.app / "Hayase"
        log = self.fixture.log.replace(str(binary), str(binary.resolve()))
        exporter = EXPORT.Exporter(self.fixture.repo, self.fixture.derived, self.fixture.packages,
                                   settings, log, self.fixture.project)
        self.assertEqual(exporter.app, self.fixture.app.resolve())
        self.assertIn(self.fixture.package_object.resolve(), exporter.inputs)

    def test_force_load_archive_preserves_flag_when_link_operand_uses_alias(self):
        alias = self.alias_paths()
        self.fixture.log += " " + shlex.join(["-Xlinker", "-force_load", "-Xlinker",
                                             str(alias(self.fixture.archive))])
        _, config = self.fixture.export()
        flags = config["NXLinkerFlags"]
        archive = "$(SRCROOT)/Config/Dependencies/Libraries/libAux.a"
        self.assertEqual(flags[flags.index(archive) - 1], "-force_load")

    def test_relative_compiler_paths_are_resolved_against_checkout_not_process_cwd(self):
        for path in (self.fixture.source_list, self.fixture.module_map, self.fixture.header.parent):
            relative = os.path.relpath(path, self.fixture.repo).replace(os.sep, "/")
            self.fixture.log = self.fixture.log.replace(path.as_posix(), relative)
        exporter, config = self.fixture.export()
        self.assertIn(Path("Hayase/Source/App Delegate.swift"), exporter.source_paths)
        self.assertIn("-I$(SRCROOT)/Config/Dependencies/SourcePackages/Clang Helper/include", config["NXSwiftFlags"])
        self.assertTrue(any(arg.startswith("-fmodule-map-file=$(SRCROOT)/") for arg in config["NXSwiftFlags"]))

    def test_realistic_link_filelist_preserves_paths_with_spaces(self):
        exporter = self.fixture.exporter()
        self.assertEqual(set(exporter.inputs), {
            self.fixture.app_object.resolve(), self.fixture.package_object.resolve(), self.fixture.extra_object.resolve(),
        })
        self.assertEqual(Path(exporter.swift[0]).name, "swiftc")

    def test_response_files_expand_recursively_without_splitting_quoted_paths(self):
        inner = self.fixture.write(self.fixture.root / "inner response", shlex.join(["-I", str(self.fixture.products)]))
        outer = self.fixture.write(self.fixture.root / "outer response", shlex.join(["@" + str(inner), "-module-name", "Hayase"]))
        self.assertEqual(EXPORT.expand_responses(["@" + str(outer)], self.fixture.repo),
                         ["-I", str(self.fixture.products), "-module-name", "Hayase"])

    def test_dyld_runtime_paths_are_not_treated_as_response_files(self):
        runtime_paths = ["@rpath/NodeMobile.framework/NodeMobile", "@executable_path/Frameworks", "@loader_path/../Frameworks"]
        response = self.fixture.write(self.fixture.root / "real response", shlex.join(["-module-name", "Hayase"]))
        self.assertEqual(EXPORT.expand_responses([*runtime_paths, "@" + str(response)], self.fixture.repo),
                         [*runtime_paths, "-module-name", "Hayase"])

    def test_linker_lto_output_is_not_a_link_input(self):
        lto_output = self.fixture.target_temp / "Objects-normal/arm64/Hayase_lto.o"
        raw, inputs = EXPORT.linker_inputs([
            "/usr/bin/clang", "-filelist", str(self.fixture.link_list),
            "-Wl,-object_path_lto," + lto_output.as_posix(), str(self.fixture.archive),
            "-o", str(self.fixture.app / "Hayase"),
        ], self.fixture.repo)
        self.assertIn("-object_path_lto", raw)
        self.assertNotIn(lto_output.resolve(), inputs)
        self.assertEqual(set(inputs), {self.fixture.app_object.resolve(), self.fixture.package_object.resolve(),
                                       self.fixture.extra_object.resolve(), self.fixture.archive.resolve()})

    def test_architecture_verification_covers_generated_archives_copied_libraries_and_frameworks(self):
        exporter, _ = self.fixture.export()
        expected = {exporter.deps / "Libraries/libSwiftSoup.a", exporter.deps / "Libraries/libAux.a",
                    exporter.deps / "Frameworks/NodeMobile.framework/NodeMobile",
                    exporter.deps / "Frameworks/StaticKit.framework/StaticKit"}
        self.assertEqual(set(self.fixture.architecture_checks), expected)

    def test_lipo_contract_rejects_binary_after_architecture_list(self):
        with self.assertRaisesRegex(AssertionError, "Invalid lipo verification command"):
            self.fixture.run("xcrun", "lipo", "-verify_arch", "arm64", self.fixture.archive)

    def test_generated_sources_inside_checkout_build_directory_are_exported_as_generated(self):
        target_temp = self.fixture.repo / "build/DerivedData/Build/Intermediates.noindex/Hayase.build/Release-iphoneos/Hayase.build"
        self.fixture.settings["TARGET_TEMP_DIR"] = str(target_temp)
        generated = self.fixture.write(target_temp / "DerivedSources/GeneratedAssetSymbols.swift", "import UIKit\n")
        self.fixture.source_list.write_text(self.fixture.source_list.read_text() + generated.as_posix() + "\n")
        exporter = self.fixture.exporter()
        exporter.sources_and_resources()
        expected = Path("Generated/DerivedSources/GeneratedAssetSymbols.swift")
        self.assertIn(expected, exporter.source_paths)
        self.assertTrue((self.fixture.project / expected).is_file())

    def test_export_keeps_editable_sources_and_excludes_old_application_objects(self):
        exporter, config = self.fixture.export()
        actual = {p.relative_to(self.fixture.project).as_posix() for p in self.fixture.project.rglob("*.swift")
                  if p.relative_to(self.fixture.project).parts[0] not in {"Config", "Resources"}}
        self.assertEqual(actual, {"Hayase/Source/App Delegate.swift", "CoreDataService/Source/CoreData.swift"})
        self.assertEqual(len(self.fixture.archive_calls), 1)
        call = self.fixture.archive_calls[0]
        self.assertIn(str(self.fixture.package_object.resolve()), call)
        self.assertIn(str(self.fixture.extra_object.resolve()), call)
        self.assertNotIn(str(self.fixture.app_object.resolve()), call)
        self.assertIn("SwiftSoup", exporter.lib_names)
        self.assertIn("Aux", exporter.lib_names)
        self.assertFalse(list(self.fixture.project.rglob("*.o")))
        self.assertFalse((self.fixture.project / "Component").exists())
        self.assertEqual(config["NXBundleInfo"], self.fixture.info)

    def test_compiled_resources_are_preserved_without_old_executable_or_signatures(self):
        self.fixture.export()
        resources = self.fixture.project / "Resources"
        self.assertTrue((resources / "Model.momd/compiled resource").exists())
        self.assertTrue((resources / "Base.lproj/Main.storyboardc/compiled resource").exists())
        self.assertTrue((resources / "SwiftSoup_SwiftSoup.bundle/resource.txt").exists())
        self.assertTrue((resources / "Twemoji/flags.json").exists())
        self.assertTrue((resources / "Nunito-Variable.ttf").exists())
        for excluded in ("Hayase", "Info.plist", "_CodeSignature", "embedded.mobileprovision"):
            self.assertFalse((resources / excluded).exists(), excluded)

    def test_static_frameworks_and_embedded_dynamic_frameworks_have_portable_search_paths(self):
        exporter, config = self.fixture.export()
        self.assertTrue((self.fixture.project / "Resources/Frameworks/NodeMobile.framework/NodeMobile").exists())
        self.assertTrue((self.fixture.project / "Config/Dependencies/Frameworks/StaticKit.framework/StaticKit").exists())
        self.assertEqual(exporter.framework_names, {"NodeMobile", "StaticKit"})
        for expected in ("-framework", "NodeMobile", "StaticKit", "Foundation", "-lz", "-lAux",
                         "-F$(SRCROOT)/Config/Dependencies/Frameworks", "-F$(SRCROOT)/Resources/Frameworks"):
            self.assertIn(expected, config["NXLinkerFlags"])
        self.assertFalse(any(arg.startswith(("-Wl,", "-Xlinker")) for arg in config["NXLinkerFlags"]))
        self.assertFalse((self.fixture.project / "Config/Dependencies/Frameworks/Foundation.framework").exists())

    def test_stripped_embedded_framework_does_not_replace_unstripped_link_input_metadata(self):
        embedded = self.fixture.app / "Frameworks/NodeMobile.framework"
        shutil.rmtree(embedded / "Headers")
        shutil.rmtree(embedded / "Modules")
        exporter, config = self.fixture.export()
        staged = self.fixture.project / "Config/Dependencies/Frameworks/NodeMobile.framework"
        self.assertTrue((staged / "Headers/NodeMobile.h").is_file())
        self.assertTrue((staged / "Modules/module.modulemap").is_file())
        self.assertTrue((staged / "NodeMobile").is_file())
        self.assertTrue((self.fixture.project / "Resources/Frameworks/NodeMobile.framework/NodeMobile").is_file())
        self.assertEqual(exporter.portable(self.fixture.dynamic / "Headers/NodeMobile.h"),
                         "$(SRCROOT)/Config/Dependencies/Frameworks/NodeMobile.framework/Headers/NodeMobile.h")
        self.assertIn("-F$(SRCROOT)/Config/Dependencies/Frameworks", config["NXSwiftFlags"])

    def test_absolute_clang_module_map_headers_are_relocated(self):
        _, config = self.fixture.export()
        maps = list((self.fixture.project / "Config/Dependencies/ModuleMaps").rglob("*.modulemap"))
        self.assertEqual(len(maps), 1)
        text = maps[0].read_text()
        self.assertNotIn(self.fixture.header.as_posix(), text)
        self.assertNotIn("$(SRCROOT)", text)
        self.assertIn("CThing.h", text)
        relative_header = text.split('header "', 1)[1].split('"', 1)[0]
        self.assertTrue((maps[0].parent / relative_header).resolve().is_file())
        self.assertTrue(any(arg.startswith("-fmodule-map-file=$(SRCROOT)/") for arg in config["NXSwiftFlags"]))

    def test_readonly_inputs_are_writable_only_in_staged_export(self):
        source_map = self.fixture.write(self.fixture.header.parent / "module.modulemap",
                                       self.fixture.module_map.read_text())
        self.fixture.tracked_files.append("include/module.modulemap")
        self.fixture.log = self.fixture.log.replace(self.fixture.module_map.as_posix(), source_map.as_posix())
        originals = {path: (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
                     for path in (source_map, self.fixture.header, self.fixture.source)}
        for path, (_, mode) in originals.items():
            self.addCleanup(path.chmod, mode)
            path.chmod(stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
        exporter, _ = self.fixture.export()
        for path, (contents, _) in originals.items():
            self.assertEqual(path.read_bytes(), contents)
            self.assertFalse(path.stat().st_mode & stat.S_IWUSR)
        staged_map = exporter.deps / "SourcePackages/Clang Helper/include/module.modulemap"
        self.assertTrue(staged_map.stat().st_mode & stat.S_IWUSR)
        self.assertNotIn(self.fixture.header.as_posix(), staged_map.read_text())
        self.assertTrue((exporter.project / "Hayase/Source/App Delegate.swift").stat().st_mode & stat.S_IWUSR)

    def test_copying_readonly_executable_keeps_execution_bits(self):
        source = self.fixture.write(self.fixture.root / "tool", "tool binary")
        mode = stat.S_IMODE(source.stat().st_mode)
        self.addCleanup(source.chmod, mode)
        source.chmod(stat.S_IRUSR | stat.S_IXUSR)
        original = stat.S_IMODE(source.stat().st_mode)
        dest = self.fixture.root / "copied tool"
        self.addCleanup(lambda: dest.chmod(mode) if dest.exists() else None)
        EXPORT.copy_tree(source, dest)
        self.assertTrue(dest.stat().st_mode & stat.S_IWUSR)
        self.assertEqual(dest.stat().st_mode & stat.S_IXUSR, original & stat.S_IXUSR)
        if os.name != "nt":  # Windows chmod only supports its read-only attribute.
            self.assertEqual(stat.S_IMODE(dest.stat().st_mode), original | stat.S_IWUSR)
        self.assertEqual(stat.S_IMODE(source.stat().st_mode), original)

    def test_unused_package_example_modulemap_is_not_rewritten(self):
        entry = "examples/Pods/Target Support Files/Example.modulemap"
        contents = 'module Example { umbrella header "missing-example-only.h" export * }\n'
        example = self.fixture.write(self.fixture.package / entry, contents)
        mode = stat.S_IMODE(example.stat().st_mode)
        self.addCleanup(example.chmod, mode)
        example.chmod(stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
        self.fixture.tracked_files.append(entry)
        exporter, config = self.fixture.export()
        self.assertEqual((exporter.deps / "SourcePackages/Clang Helper" / entry).read_text(), contents)
        self.assertFalse(any("Example.modulemap" in arg for arg in config["NXSwiftFlags"]))

    def test_include_discovered_modulemap_is_relocated_without_explicit_map_flag(self):
        source_map = self.fixture.write(self.fixture.header.parent / "module.modulemap",
                                       self.fixture.module_map.read_text())
        self.fixture.tracked_files.append("include/module.modulemap")
        explicit_flag = shlex.join(["-Xcc", "-fmodule-map-file=" + self.fixture.module_map.as_posix()])
        self.fixture.log = self.fixture.log.replace(explicit_flag, "")
        exporter, _ = self.fixture.export()
        staged = exporter.deps / "SourcePackages/Clang Helper/include/module.modulemap"
        self.assertNotIn(self.fixture.header.as_posix(), staged.read_text())
        relative_header = staged.read_text().split('header "', 1)[1].split('"', 1)[0]
        self.assertTrue((staged.parent / relative_header).is_file())
        self.assertEqual(source_map.read_text(), self.fixture.module_map.read_text())

    def test_external_include_modulemap_is_relocated_after_include_copy(self):
        include = self.fixture.root / "External Headers"
        self.fixture.write(include / "module.modulemap", self.fixture.module_map.read_text())
        include_flag = shlex.join(["-Xcc", "-I" + include.as_posix()])
        self.fixture.log = self.fixture.log.replace("-D SWIFT_PACKAGE", include_flag + " -D SWIFT_PACKAGE")
        exporter, _ = self.fixture.export()
        staged = next((exporter.deps / "Includes").rglob("module.modulemap"))
        self.assertNotIn(self.fixture.header.as_posix(), staged.read_text())
        relative_header = staged.read_text().split('header "', 1)[1].split('"', 1)[0]
        self.assertTrue((staged.parent / relative_header).resolve().is_file())

    def test_empty_and_filtered_include_directories_do_not_block_export(self):
        include = self.fixture.root / "DerivedSources"
        include.mkdir()
        include_flag = shlex.join(["-Xcc", "-I" + include.as_posix()])
        self.fixture.log = self.fixture.log.replace("-D SWIFT_PACKAGE", include_flag + " -D SWIFT_PACKAGE")
        for filtered in (False, True):
            with self.subTest(filtered=filtered):
                if filtered:
                    self.fixture.write(include / "Ignored.swift", "let excluded = true\n")
                    self.fixture.write(include / "Ignored.txt", "not import metadata\n")
                exporter, _ = self.fixture.export()
                staged = next((exporter.deps / "Includes").iterdir())
                self.assertTrue(staged.is_dir())
                self.assertEqual(list(staged.iterdir()), [])

    def test_nested_include_modulemap_and_private_companion_are_relocated(self):
        directory = self.fixture.header.parent / "Nested"
        for name in ("module.modulemap", "module.private.modulemap"):
            self.fixture.write(directory / name, self.fixture.module_map.read_text())
            self.fixture.tracked_files.append("include/Nested/" + name)
        exporter, _ = self.fixture.export()
        for name in ("module.modulemap", "module.private.modulemap"):
            staged = exporter.deps / "SourcePackages/Clang Helper/include/Nested" / name
            self.assertNotIn(self.fixture.header.as_posix(), staged.read_text())
            relative_header = staged.read_text().split('header "', 1)[1].split('"', 1)[0]
            self.assertTrue((staged.parent / relative_header).resolve().is_file())

    def test_explicit_modulemap_private_companion_is_relocated(self):
        self.fixture.write(self.fixture.module_map.with_name("module.private.modulemap"),
                           self.fixture.module_map.read_text())
        exporter, _ = self.fixture.export()
        staged = next((exporter.deps / "ModuleMaps").rglob("module.private.modulemap"))
        self.assertNotIn(self.fixture.header.as_posix(), staged.read_text())
        relative_header = staged.read_text().split('header "', 1)[1].split('"', 1)[0]
        self.assertTrue((staged.parent / relative_header).resolve().is_file())

    def test_active_modulemap_with_missing_header_still_fails(self):
        self.fixture.module_map.write_text('module ClangHelper { header "missing-active.h" export * }\n')
        with self.assertRaisesRegex(ValueError, "Missing modulemap header/umbrella"):
            self.fixture.export()

    def test_relative_modulemap_headers_keep_their_original_relationship(self):
        # A generated map references a header outside its own directory.
        import os
        relative = os.path.relpath(self.fixture.header, self.fixture.module_map.parent).replace(os.sep, "/")
        self.fixture.module_map.write_text('module ClangHelper { header "' + relative + '" export * }\n')
        self.fixture.export()
        module = next((self.fixture.project / "Config/Dependencies/ModuleMaps").rglob("*.modulemap"))
        path = module.read_text().split('header "', 1)[1].split('"', 1)[0]
        self.assertTrue((module.parent / path).resolve().is_file())
        self.assertTrue((module.parent / path).resolve().is_relative_to(self.fixture.project.resolve()))

    def test_unrelated_cached_package_sources_are_not_exported(self):
        self.fixture.write(self.fixture.packages / "checkouts/unrelated/Sensitive.swift", "cached unrelated source")
        self.fixture.export()
        self.assertFalse((self.fixture.project / "Config/Dependencies/SourcePackages/unrelated").exists())

    def test_sdk_framework_search_path_does_not_redistribute_apple_framework(self):
        self.fixture.log = self.fixture.log.replace("-framework Foundation", "-F " +
            shlex.quote((self.fixture.sdk / "System/Library/Frameworks").as_posix()) + " -framework Foundation")
        self.fixture.export()
        self.assertFalse((self.fixture.project / "Config/Dependencies/Frameworks/Foundation.framework").exists())

    def test_serialized_modules_are_removed_but_textual_interfaces_remain(self):
        self.fixture.export()
        module = self.fixture.project / "Config/Dependencies/Modules/SwiftSoup.swiftmodule"
        self.assertTrue((module / self.fixture.interface.name).exists())
        self.assertFalse((module / self.fixture.serialized_module.name).exists())

    def test_large_project_disables_unpopulated_nyxian_driver_filelists(self):
        # Exceed Swift's legacy 128-input threshold with Hayase's current size.
        additional = [self.fixture.write(self.fixture.repo / f"Hayase/Source/File {index}.swift",
                                         f"struct Fixture{index} {{}}\n") for index in range(287)]
        self.fixture.source_list.write_text(self.fixture.source_list.read_text()
                                            + "".join(path.as_posix() + "\n" for path in additional))
        exporter, config = self.fixture.export()
        self.assertEqual(len(exporter.source_paths), 289)
        flags = config["NXSwiftFlags"]
        self.assertEqual(EXPORT.option_values(flags, "-driver-filelist-threshold"), ["2147483647"])
        self.assertEqual(flags.count("-whole-module-optimization"), 1)
        self.assertEqual(EXPORT.option_values(flags, "-num-threads"), ["0"])
        self.assertIn("-O", flags)
        self.assertFalse(any(arg in {"-filelist", "-primary-filelist", "-output-filelist",
                                     "-supplementary-output-file-map"} for arg in flags))
        archive = self.fixture.root / "large-export.zip"
        EXPORT.zip_project(self.fixture.project, archive)
        with zipfile.ZipFile(archive) as zipped:
            persisted = plistlib.loads(zipped.read("Hayase/Config/Project.plist"))
            self.assertEqual(persisted["NXSwiftFlags"], flags)
            self.assertEqual(sum(name.endswith(".swift") and "/Config/" not in name
                                 for name in zipped.namelist()), 289)

    def test_smoke_test_preserves_filelist_threshold_and_inline_source_paths(self):
        exporter, config = self.fixture.export()
        output = self.fixture.root / "smoke output"
        output.mkdir()
        runtime = str(self.fixture.root / "toolchain/lib/swift")

        def environment(*args):
            if args == ("xcrun", "--sdk", "iphoneos", "--show-sdk-path"):
                return str(self.fixture.sdk)
            if args == ("xcrun", "swiftc", "-print-target-info"):
                return json.dumps({"paths": {"runtimeResourcePath": runtime}})
            if args[:2] == ("xcrun", "swiftc") and args[-1] == "-driver-print-jobs":
                obj = str(output / "Hayase.o")
                frontend = ["swift-frontend", "-frontend", "-c", "-module-name", "Hayase",
                            *(str(exporter.project / path) for path in exporter.source_paths), "-o", obj]
                linker = ["ld", obj, "-o", str(output / "Hayase-export-smoke")]
                return "\n".join(shlex.join(job) for job in (frontend, linker))
            raise AssertionError("Unexpected toolchain query: " + repr(args))

        with patch.object(EXPORT, "run", side_effect=environment), \
                patch.object(EXPORT.subprocess, "run") as compiler:
            driver_plan = EXPORT.smoke_test(exporter, config, output)
        compiler.assert_called_once()
        args = compiler.call_args.args[0]
        self.assertEqual(args[:2], ["xcrun", "swiftc"])
        self.assertEqual(EXPORT.option_values(args, "-driver-filelist-threshold"), ["2147483647"])
        self.assertIn("-whole-module-optimization", args)
        self.assertEqual(EXPORT.option_values(args, "-num-threads"), ["0"])
        for source in exporter.source_paths:
            self.assertEqual(args.count(str(exporter.project / source)), 1)
        self.assertIn(runtime, args)
        self.assertIn(str(output / "smoke-module-cache"), args)
        self.assertFalse(any("$(" in arg for arg in args))
        self.assertNotIn("-driver-print-jobs", args)  # The actual smoke compile must still run.
        self.assertTrue(compiler.call_args.kwargs["check"])
        self.assertEqual(driver_plan, {"compileJobs": 1, "appObjectInputs": 1, "hostLinkArgumentCount": 3})
        self.assertTrue((output / "export-driver-jobs.log").is_file())

    def test_zip_has_exactly_one_project_root_and_valid_config(self):
        self.fixture.export()
        archive = self.fixture.root / "Hayase-Nyxian-Source.zip"
        EXPORT.zip_project(self.fixture.project, archive)
        with zipfile.ZipFile(archive) as zipped:
            self.assertIsNone(zipped.testzip())
            self.assertEqual({name.split("/")[0] for name in zipped.namelist()}, {"Hayase"})
            config = plistlib.loads(zipped.read("Hayase/Config/Project.plist"))
            self.assertEqual(config["NXProjectFormat"], "NXAvixR2")
            self.assertEqual(config["NXProjectScheme"], "Application")
            self.assertEqual(EXPORT.option_values(config["NXSwiftFlags"], "-driver-filelist-threshold"),
                             ["2147483647"])
            self.assertIn("-whole-module-optimization", config["NXSwiftFlags"])
            self.assertEqual(EXPORT.option_values(config["NXSwiftFlags"], "-num-threads"), ["0"])
            self.assertNotIn("Hayase/Resources/Hayase", zipped.namelist())

    def test_missing_framework_fails_instead_of_silently_creating_incomplete_archive(self):
        shutil.rmtree(self.fixture.static)
        exporter = self.fixture.exporter()
        exporter.sources_and_resources()
        exporter.archive_objects()
        with self.assertRaisesRegex(ValueError, "Linked framework not found: StaticKit"):
            exporter.frameworks_and_link_flags()

    def test_missing_textual_interface_fails(self):
        self.fixture.interface.unlink()
        with self.assertRaisesRegex(ValueError, "No arm64 textual interface"):
            self.fixture.export()

    def test_missing_runtime_resource_fails(self):
        (self.fixture.app / "Assets.car").unlink()
        with self.assertRaisesRegex(ValueError, "Missing compiled runtime resource: Assets.car"):
            self.fixture.exporter().sources_and_resources()

    def test_ci_absolute_flags_fail_validation(self):
        exporter, config = self.fixture.export()
        for arg in ("-I/Users/builder/DerivedData", "-F/Applications/Xcode.app/frameworks",
                    "-fmodule-map-file=/private/tmp/module.modulemap", "-I/var/folders/build/include"):
            with self.subTest(arg=arg):
                invalid = dict(config, NXSwiftFlags=config["NXSwiftFlags"] + [arg])
                with self.assertRaisesRegex(ValueError, "CI path leaked"):
                    EXPORT.validate_layout(self.fixture.project, invalid, exporter.source_paths)

    def test_unexpected_sources_outside_config_resources_fail_source_discovery(self):
        exporter, config = self.fixture.export()
        self.fixture.write(self.fixture.project / "Unexpected.swift", "import Foundation\n")
        with self.assertRaisesRegex(ValueError, "source discovery differs"):
            EXPORT.validate_layout(self.fixture.project, config, exporter.source_paths)

    def test_configuration_and_resource_sources_are_not_compiled(self):
        exporter, config = self.fixture.export()
        self.fixture.write(self.fixture.project / "Config/Nested/Package.swift", "let metadata = true\n")
        self.fixture.write(self.fixture.project / "Resources/node_modules/example/test.c", "void irrelevant(void) {}\n")
        EXPORT.validate_layout(self.fixture.project, config, exporter.source_paths)

    def test_unexported_interface_autolink_library_fails(self):
        self.fixture.interface.write_text("// swift-module-flags: -module-link-name MissingPackage\n")
        with self.assertRaisesRegex(ValueError, "unexported library: MissingPackage"):
            self.fixture.export()


class SingleObjectDriverPlanTests(unittest.TestCase):
    def setUp(self):
        self.sources = ["/project with spaces/First.swift", "/project with spaces/Second.swift"]
        self.obj = "/temporary path/Hayase.o"
        self.output = "/output with spaces/Hayase-export-smoke"
        self.frontend = ["/toolchain/swift-frontend", "-frontend", "-c", *self.sources,
                         "-module-name", "Hayase", "-o", self.obj]
        self.linker = ["/toolchain/clang", self.obj, "-arch", "arm64", "-o", self.output]

    def validate(self, frontend=None, linker=None, extra=()):
        jobs = [self.frontend if frontend is None else frontend,
                self.linker if linker is None else linker, *extra]
        plan = "\n".join(shlex.join(job) for job in jobs)
        return EXPORT.validate_single_object_plan(plan, self.sources, self.output)

    def test_quoted_paths_are_preserved_in_single_object_plan(self):
        self.assertEqual(self.validate(), {"compileJobs": 1, "appObjectInputs": 1,
                                          "hostLinkArgumentCount": 5})

    def test_emit_object_spelling_is_supported(self):
        frontend = ["-emit-object" if arg == "-c" else arg for arg in self.frontend]
        self.assertEqual(self.validate(frontend=frontend)["appObjectInputs"], 1)

    def test_shell_escaped_output_path_is_decoded_before_matching(self):
        plan = shlex.join(self.frontend) + "\n" + " ".join(arg.replace(" ", "\\ ")
                                                         for arg in self.linker)
        self.assertEqual(EXPORT.validate_single_object_plan(plan, self.sources, self.output)["appObjectInputs"], 1)

    def test_unmatched_quote_in_diagnostic_does_not_hide_valid_jobs(self):
        plan = "warning: can't use an unrelated option\n" + "\n".join(
            shlex.join(job) for job in (self.frontend, self.linker))
        self.assertEqual(EXPORT.validate_single_object_plan(plan, self.sources, self.output)["compileJobs"], 1)

    def test_other_module_jobs_are_not_counted_as_app_compilations(self):
        dependency = ["Foundation" if arg == "Hayase" else arg for arg in self.frontend]
        self.assertEqual(self.validate(extra=[dependency])["compileJobs"], 1)

    def test_missing_compile_job_fails(self):
        with self.assertRaisesRegex(ValueError, "one Hayase compilation"):
            self.validate(frontend=[])

    def test_multiple_app_compile_jobs_fail(self):
        with self.assertRaisesRegex(ValueError, "one Hayase compilation"):
            self.validate(extra=[self.frontend])

    def test_omitted_source_fails(self):
        with self.assertRaisesRegex(ValueError, "omits app source"):
            self.validate(frontend=[arg for arg in self.frontend if arg != self.sources[1]])

    def test_primary_file_and_temporary_output_maps_fail(self):
        for flag in ("-primary-file", "-filelist", "-primary-filelist", "-output-filelist",
                     "-supplementary-output-file-map"):
            with self.subTest(flag=flag), self.assertRaisesRegex(ValueError, "primary-file jobs"):
                self.validate(frontend=self.frontend + [flag, "/temporary/input list"])

    def test_multiple_object_outputs_fail(self):
        with self.assertRaisesRegex(ValueError, "single compiled app object"):
            self.validate(frontend=self.frontend + ["-o", "/temporary/Second.o"])

    def test_non_object_output_fails(self):
        frontend = ["/temporary/Hayase.bc" if arg == self.obj else arg for arg in self.frontend]
        with self.assertRaisesRegex(ValueError, "single compiled app object"):
            self.validate(frontend=frontend)

    def test_missing_or_duplicate_object_in_link_job_fails(self):
        for linker in ([arg for arg in self.linker if arg != self.obj], self.linker + [self.obj]):
            with self.subTest(linker=linker), self.assertRaisesRegex(ValueError, "single app object inline"):
                self.validate(linker=linker)

    def test_linker_filelist_fails(self):
        with self.assertRaisesRegex(ValueError, "temporary file list"):
            self.validate(linker=self.linker + ["-filelist", "/temporary/object list"])

    def test_wrong_or_duplicate_link_job_fails(self):
        linker = ["/other/application" if arg == self.output else arg for arg in self.linker]
        with self.assertRaisesRegex(ValueError, "single app object inline"):
            self.validate(linker=linker)
        with self.assertRaisesRegex(ValueError, "single app object inline"):
            self.validate(extra=[self.linker])


if __name__ == "__main__":
    unittest.main()
