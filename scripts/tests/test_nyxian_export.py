"""Portable contract tests for the Nyxian export (no Apple toolchain required)."""
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import shutil
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
            return ""
        if args[:2] == ["git", "-C"] and args[-2:] == ["ls-files", "-z"]:
            return "include/CThing.h\0SourcePackage.swift\0"
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
                    "-fmodule-map-file=/private/tmp/module.modulemap"):
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


if __name__ == "__main__":
    unittest.main()
