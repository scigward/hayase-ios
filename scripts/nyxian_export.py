#!/usr/bin/env python3
"""Convert a successful arm64 Xcode build to Nyxian's NXAvixR2 project format.

Use actual target compiler/linker inputs, not guesses about SPM product names.
No third-party Python modules are required. Run export_nyxian_source.sh normally.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import tempfile
import zipfile

NYXIAN_REVISION = "350dd8dbeb796bc0ff5bc91ef770f1a2994432e7"
CODE_SUFFIXES = {".swift", ".c", ".cpp", ".m", ".mm"}
IMPORT_SUFFIXES = {".h", ".hpp", ".hh", ".inc", ".def", ".modulemap",
                   ".swiftinterface", ".swiftdoc", ".abi.json"}
RESOURCE_REQUIREMENTS = (
    "Assets.car", "Model.momd", "Base.lproj/Main.storyboardc",
    "Base.lproj/LaunchScreen.storyboardc", "WebTorrentBackend/webtorrent-bridge.js",
    "WebTorrentBackend/torrent-client/index.js", "TorrentClientGeoIP/params.json",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args, **kwargs):
    return subprocess.check_output([str(arg) for arg in args], text=True, **kwargs).strip()


def under(path, root):
    return path.resolve().is_relative_to(root.resolve())


def expand_responses(args, cwd, depth=0):
    require(depth < 12, "Recursive Xcode response file")
    result = []
    for arg in args:
        if arg.startswith("@") and not arg.startswith(("@rpath", "@executable_path", "@loader_path")):
            path = Path(arg[1:])
            if not path.is_absolute():
                path = cwd / path
            require(path.is_file(), f"Missing response file: {path}")
            result.extend(expand_responses(shlex.split(path.read_text()), cwd, depth + 1))
        else:
            result.append(arg)
    return result


def commands(log, cwd):
    """Xcode prints the real invocations, including builtin-SwiftDriver's '--'."""
    result = []
    for line in log.splitlines():
        if not re.search(r"/(?:swiftc|clang(?:\+\+)?)\s", line):
            continue
        args = shlex.split(line.strip())
        for index, arg in enumerate(args):
            if Path(arg).name in {"swiftc", "clang", "clang++"}:
                result.append(expand_responses(args[index:], cwd))
                break
    return result


def option_values(args, option):
    return [args[i + 1] for i, arg in enumerate(args[:-1]) if arg == option]


def search_paths(args, option):
    result = []
    for i, arg in enumerate(args):
        if arg == option:
            require(i + 1 < len(args), f"Missing {option} argument")
            result.append(Path(args[i + 1]))
        elif arg.startswith(option) and len(arg) > len(option):
            result.append(Path(arg[len(option):]))
    return list(dict.fromkeys(result))


def read_filelist(path, cwd):
    result = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        candidate = Path(line)
        if not candidate.is_absolute():
            candidate = cwd / candidate
        if not candidate.exists():
            tokens = shlex.split(line)
            require(len(tokens) == 1, f"Invalid file list entry: {line}")
            candidate = Path(tokens[0])
            if not candidate.is_absolute():
                candidate = cwd / candidate
        result.append(candidate)
    return result


def linker_inputs(args, cwd):
    """Collect -filelist, direct files, and -Xlinker/-Wl arguments uniformly."""
    raw = []
    i = 1
    while i < len(args):
        arg = args[i]
        if arg == "-Xlinker":
            require(i + 1 < len(args), "Missing -Xlinker argument")
            raw.append(args[i + 1])
            i += 2
        elif arg.startswith("-Wl,"):
            raw.extend(arg[4:].split(","))
            i += 1
        else:
            raw.append(arg)
            i += 1
    objects = []
    for value in option_values(raw, "-filelist"):
        path = Path(value)
        if not path.is_absolute():
            path = cwd / path
        # File lists are one path per line, including paths containing spaces.
        objects.extend(read_filelist(path, cwd))
    non_input_options = {"-o", "-object_path_lto", "-dependency_info", "-map",
                         "-final_output", "-add_ast_path", "-serialize-diagnostics"}
    objects.extend(Path(arg) for i, arg in enumerate(raw)
                   if arg.endswith((".o", ".a")) and (i == 0 or raw[i - 1] not in non_input_options))
    return raw, list(dict.fromkeys((path if path.is_absolute() else cwd / path).resolve() for path in objects))


def copy_tree(src, dst, imports_only=False):
    """Dereference device framework symlinks; never include signing metadata."""
    require(src.exists(), f"Missing export input: {src}")
    if src.is_file():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        return
    for root, dirs, files in os.walk(src, followlinks=True):
        dirs[:] = sorted(d for d in dirs if d not in {".git", ".build", "_CodeSignature", "__MACOSX"})
        relative = Path(root).relative_to(src)
        for name in sorted(files):
            if name in {".DS_Store", "embedded.mobileprovision", "CodeResources"}:
                continue
            path = Path(root) / name
            if imports_only and not (path.suffix in IMPORT_SUFFIXES or name == "module.modulemap"):
                continue
            copy_tree(path, dst / relative / name)


def make_portable_modules(root):
    for module in root.rglob("*.swiftmodule"):
        if not module.is_dir():
            continue
        interfaces = [p for p in module.glob("arm64*.swiftinterface") if not p.name.endswith(".private.swiftinterface")]
        require(interfaces, f"No arm64 textual interface for {module.name}; enable library evolution")
        for serialized in module.glob("*.swiftmodule"):
            serialized.unlink()  # Force a different Swift compiler to load the interface.


class Exporter:
    def __init__(self, repo, derived, packages, settings, log, project):
        self.repo, self.derived, self.packages, self.project = repo, derived, packages, project
        self.settings = settings
        self.products = Path(settings["TARGET_BUILD_DIR"])
        self.app = self.products / settings["FULL_PRODUCT_NAME"]
        self.target_temp = Path(settings["TARGET_TEMP_DIR"])
        self.sdk = Path(settings["SDKROOT"])
        self.deps = project / "Config/Dependencies"
        self.mappings = []
        self.source_paths = []
        self.lib_names = set()
        self.framework_names = set()
        all_commands = commands(log, repo)
        swift = [c for c in all_commands if Path(c[0]).name == "swiftc"
                 and option_values(c, "-module-name") == ["Hayase"]]
        binary = str(self.app / settings["EXECUTABLE_NAME"])
        links = [c for c in all_commands if Path(c[0]).name.startswith("clang")
                 and option_values(c, "-o") == [binary]]
        require(swift and links, "Could not locate Hayase's actual swiftc and final clang link invocations")
        self.swift = swift[-1]
        self.raw_link, self.inputs = linker_inputs(links[-1], repo)
        self.all_commands = all_commands
        self.framework_paths = search_paths(self.raw_link, "-F") + search_paths(self.swift, "-F")
        self.library_paths = search_paths(self.raw_link, "-L")
        self.framework_paths = [p if p.is_absolute() else repo / p for p in self.framework_paths]
        self.library_paths = [p if p.is_absolute() else repo / p for p in self.library_paths]
        self.nx_link = ["-ObjC", "-rpath", "@executable_path/Frameworks"]
        self.nx_swift = []
        self.xcc = []
        lockfile = repo / "Hayase.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        require(lockfile.is_file(), "Missing resolved dependency lockfile")
        self.package_lock = json.loads(lockfile.read_text())

    def portable(self, path):
        path = path.resolve()
        if under(path, self.sdk):
            return "$(SDKROOT)/" + path.relative_to(self.sdk.resolve()).as_posix()
        for old, new in sorted(self.mappings, key=lambda pair: len(str(pair[0])), reverse=True):
            if under(path, old):
                return "$(SRCROOT)/" + (new / path.relative_to(old.resolve())).relative_to(self.project).as_posix()
        raise ValueError(f"Unmapped dependency path: {path}")

    def sources_and_resources(self):
        sources = [Path(arg) for arg in self.swift if arg.endswith(".swift")]
        for value in option_values(self.swift, "-filelist"):
            sources.extend(read_filelist(Path(value), self.repo))
        sources = list(dict.fromkeys((path if path.is_absolute() else self.repo / path).resolve() for path in sources))
        require(sources, "No actual Hayase Swift source inputs")
        for src in sources:
            require(src.is_file(), f"Missing target source: {src}")
            if under(src, self.target_temp):
                relative = Path("Generated") / src.relative_to(self.target_temp)
            elif under(src, self.repo):
                relative = src.relative_to(self.repo)
                require(relative.parts[:2] in [("Hayase", "Source"), ("CoreDataService", "Source")],
                        f"Unexpected source outside app target source roots: {relative}")
            else:
                raise ValueError(f"Unexpected generated source: {src}")
            copy_tree(src, self.project / relative)
            self.source_paths.append(relative)
        # Headers can be needed by local Swift source, even though this build has
        # an empty bridge. Do not stage Package.swift, tests or unrelated checkouts.
        for source_root in ("Hayase/Source", "CoreDataService/Source"):
            for header in (self.repo / source_root).rglob("*.h"):
                copy_tree(header, self.project / header.relative_to(self.repo))
        copy_tree(self.app, self.project / "Resources")
        for name in (self.settings["EXECUTABLE_NAME"], "Info.plist"):
            (self.project / "Resources" / name).unlink()
        for name in RESOURCE_REQUIREMENTS:
            require((self.project / "Resources" / name).exists(), f"Missing compiled runtime resource: {name}")
        info = plistlib.loads((self.app / "Info.plist").read_bytes())
        require(info["CFBundleExecutable"] == "Hayase", "Unexpected app executable/module identity")
        return info

    def archive_objects(self):
        groups = {}
        for path in self.inputs:
            require(path.is_file(), f"Missing linked dependency input: {path}")
            if under(path, self.target_temp):
                continue  # Never link the old app alongside its editable source.
            if path.suffix == ".a":
                self.stage_library(path)
                continue
            target = next((p[:-6] for p in reversed(path.parts[:-1]) if p.endswith(".build")), path.stem)
            require(re.fullmatch(r"[A-Za-z0-9_-]+", target), f"Unexpected library identity: {target}")
            groups.setdefault(target, []).append(path)
        require(groups or self.lib_names, "No static package dependencies found in final app link")
        for name, paths in sorted(groups.items()):
            require(name not in self.lib_names, f"Duplicate object/archive identity: {name}")
            dest = self.deps / "Libraries" / f"lib{name}.a"
            dest.parent.mkdir(parents=True, exist_ok=True)
            # Archiving preserves Swift autolink metadata. .o files themselves
            # cannot be exported: Nyxian.clean() deletes them from projects.
            run("xcrun", "libtool", "-static", "-o", dest, *paths)
            run("xcrun", "lipo", "-verify_arch", "arm64", dest)
            self.lib_names.add(name)
            self.nx_link.extend(["-force_load", "$(SRCROOT)/" + dest.relative_to(self.project).as_posix()])

    def stage_library(self, path):
        name = path.name.removeprefix("lib").removesuffix(".a")
        dest = self.deps / "Libraries" / path.name
        if dest.exists():
            require(sha256(dest) == sha256(path), f"Colliding library: {path.name}")
        else:
            copy_tree(path, dest)
        run("xcrun", "lipo", "-verify_arch", "arm64", dest)
        self.lib_names.add(name)
        return "$(SRCROOT)/" + dest.relative_to(self.project).as_posix()

    def stage_framework(self, source):
        name = source.stem
        dest = self.deps / "Frameworks" / source.name
        if (source.resolve(), dest) in self.mappings:
            return "$(SRCROOT)/" + (dest / name).relative_to(self.project).as_posix()
        if not dest.exists():
            # Xcode strips Headers/Modules from embedded frameworks. Import
            # metadata MUST come from the link input, not the app's stripped copy.
            copy_tree(source, dest)
        else:
            require(sha256(source / name) == sha256(dest / name), f"Colliding framework: {name}")
        self.mappings.append((source.resolve(), dest))
        run("xcrun", "lipo", "-verify_arch", "arm64", dest / name)
        self.framework_names.add(name)
        return "$(SRCROOT)/" + (dest / name).relative_to(self.project).as_posix()

    def frameworks_and_link_flags(self):
        paired = {"-framework", "-weak_framework", "-reexport_framework", "-lazy_framework"}
        i = 0
        while i < len(self.raw_link):
            arg = self.raw_link[i]
            if arg in paired:
                name = self.raw_link[i + 1]
                candidates = [p / f"{name}.framework" for p in self.framework_paths]
                candidates = [p for p in candidates if p.is_dir() and not under(p, self.sdk)]
                if candidates:
                    self.stage_framework(candidates[0])
                else:
                    sdk_framework = self.sdk / "System/Library/Frameworks" / f"{name}.framework"
                    require(sdk_framework.exists(), f"Linked framework not found: {name}")
                self.nx_link.extend([arg, name])
                i += 2
                continue
            if arg.startswith("-l") and not arg.startswith(("-lazy", "-linker")):
                name = arg[2:]
                if name not in self.lib_names:
                    candidate = next((p / f"lib{name}.a" for p in self.library_paths
                                      if (p / f"lib{name}.a").exists() and not under(p, self.sdk)), None)
                    if candidate:
                        self.stage_library(candidate)
                    else:
                        # System/compiler runtime libraries are provided by the
                        # device SDK/toolchain; never redistribute Apple's SDK.
                        require((self.sdk / "usr/lib" / f"lib{name}.tbd").exists()
                                or name.startswith(("swift", "clang_rt")), f"Unresolved linked library: {name}")
                if not name.startswith(("swift", "clang_rt")):
                    self.nx_link.append(arg)
            i += 1
        # Static binary products may be passed as a direct framework binary (or
        # -force_load) instead of the conventional '-framework Name' spelling.
        for arg in self.raw_link:
            path = Path(arg)
            if path.is_absolute() and path.is_file() and any(p.endswith(".framework") for p in path.parts[:-1]):
                framework = next(p for p in path.parents if p.suffix == ".framework")
                if not under(framework, self.sdk) and path.name == framework.stem:
                    if arg in option_values(self.raw_link, "-force_load"):
                        self.nx_link.append("-force_load")
                    self.nx_link.append(self.stage_framework(framework))
        # Explicit .a paths are not necessarily expressed as -l in Xcode.
        for path in self.inputs:
            if path.suffix == ".a" and not under(path, self.target_temp):
                flag = "-force_load" if str(path) in option_values(self.raw_link, "-force_load") else None
                if flag:
                    self.nx_link.append(flag)
                self.nx_link.append(self.stage_library(path))
        self.nx_link.extend(["-L$(SRCROOT)/Config/Dependencies/Libraries",
                             "-F$(SRCROOT)/Config/Dependencies/Frameworks",
                             "-F$(SRCROOT)/Resources/Frameworks"])
        make_portable_modules(self.project / "Resources/Frameworks")
        make_portable_modules(self.deps / "Frameworks")

    def import_metadata(self):
        # Preserve source-package headers and licenses at their original relative
        # locations for generated modulemaps and relative #include directives.
        checkouts = self.packages / "checkouts"
        require(checkouts.is_dir(), "Missing resolved Swift package checkouts")
        # The cache is shared between builds; never export unrelated/stale
        # package source just because it remains in a checkout directory.
        pins = self.package_lock.get("pins", self.package_lock.get("object", {}).get("pins", []))
        active = set()
        for pin in pins:
            active.add(pin.get("identity", pin.get("package", "")).casefold())
            location = pin.get("location", pin.get("repositoryURL", ""))
            active.add(location.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git").casefold())
        for package in sorted(checkouts.iterdir()):
            if not package.is_dir() or package.name.casefold() not in active:
                continue
            tracked = run("git", "-C", package, "ls-files", "-z").split("\0")
            dest = self.deps / "SourcePackages" / package.name
            for entry in tracked:
                if not entry:
                    continue
                path = package / entry
                if path.is_file() and (path.suffix in IMPORT_SUFFIXES | CODE_SUFFIXES
                                       or re.search(r"license|copying|notice", path.name, re.I)):
                    copy_tree(path, dest / entry)
            self.mappings.append((package.resolve(), dest))
        # SPM leaves compiled Swift modules beside its per-target object files.
        for module in sorted(self.products.glob("*.swiftmodule")):
            if module.stem != "Hayase":
                copy_tree(module, self.deps / "Modules" / module.name)
        make_portable_modules(self.deps / "Modules")
        self.mappings.append((self.products.resolve(), self.deps / "Modules"))
        # Gather transitive Clang maps from all package Swift invocations, not
        # just direct imports in Hayase's invocation.
        maps = set()
        for command in self.all_commands:
            for arg in command:
                if arg.startswith("-fmodule-map-file="):
                    maps.add(Path(arg.partition("=")[2]).resolve())
        for index, source in enumerate(sorted(maps)):
            if under(source, self.sdk):
                continue
            require(source.is_file(), f"Missing Clang module map: {source}")
            # Framework maps/headers were already copied with their framework.
            if any(under(source, old) for old, _ in self.mappings if old.suffix == ".framework"):
                continue
            try:
                portable = self.portable(source)
                require((self.project / portable.removeprefix("$(SRCROOT)/")).is_file(), "Map not staged")
            except ValueError:
                target = self.deps / "ModuleMaps" / str(index)
                copy_tree(source.parent, target, imports_only=True)
                self.mappings.append((source.parent.resolve(), target))
                portable = self.portable(source)
            self.xcc.extend(["-fmodule-map-file=" + portable])
        # Relocate absolute modulemap header/umbrella paths. SDK maps remain SDK
        # maps; no SDK headers copied into the archive.
        module_maps = list(self.deps.rglob("*.modulemap")) + list((self.project / "Resources/Frameworks").rglob("*.modulemap"))
        for module_map in module_maps:
            origin = next((old / module_map.relative_to(new) for old, new in
                           sorted(self.mappings, key=lambda pair: len(str(pair[1])), reverse=True)
                           if under(module_map, new)), None)
            # Embedded runtime metadata is not an import input; unstripped
            # framework maps in Config are the ones the compiler uses.
            if origin is None:
                continue
            text = module_map.read_text()
            def relocate(match):
                value = match.group(1)
                path = Path(value) if Path(value).is_absolute() else origin.parent / value
                if not path.exists():
                    # Framework umbrella headers are resolved in Headers/, not
                    # the Modules/ directory. Preserve that framework syntax.
                    framework = next((p for p in origin.parents if p.suffix == ".framework"), None)
                    if framework and (framework / "Headers" / value).exists():
                        return match.group(0)
                require(path.exists(), f"Missing modulemap header/umbrella: {path}")
                mapped = self.portable(path)
                require(mapped.startswith("$(SRCROOT)/"), f"Unexpected SDK absolute header in modulemap: {path}")
                destination = self.project / mapped.removeprefix("$(SRCROOT)/")
                require(destination.exists(), f"Missing relocated modulemap header: {path}")
                # Clang does not expand Nyxian variables inside modulemaps.
                relative = os.path.relpath(destination, module_map.parent).replace(os.sep, "/")
                return match.group(0).replace('"' + value + '"', '"' + relative + '"')
            module_map.write_text(re.sub(r'(?:umbrella(?:\s+header)?|header)\s+"([^"\n]+)"', relocate, text))
        app_xcc = option_values(self.swift, "-Xcc")
        for path in search_paths(app_xcc, "-I") + search_paths(self.swift, "-I"):
            if under(path, self.sdk):
                self.xcc.append("-I" + self.portable(path))
            elif path.resolve() == self.products.resolve():
                continue
            elif path.is_dir():
                # Include metadata only. A map mapping can already cover it.
                try:
                    mapped = self.portable(path)
                    require((self.project / mapped.removeprefix("$(SRCROOT)/")).exists(), "Import directory not staged")
                except ValueError:
                    dest = self.deps / "Includes" / hashlib.sha256(str(path).encode()).hexdigest()[:12]
                    copy_tree(path, dest, imports_only=True)
                    self.mappings.append((path.resolve(), dest))
                    mapped = self.portable(path)
                self.xcc.append("-I" + mapped)
        for arg in app_xcc:
            if arg.startswith("-D"):
                self.xcc.append(arg)
        for option in ("-D", "-enable-upcoming-feature", "-enable-experimental-feature"):
            for value in option_values(self.swift, option):
                self.nx_swift.extend([option, value])
        for flag in ("-enable-bare-slash-regex", "-enable-testing", "-enable-experimental-cxx-interop"):
            if flag in self.swift:
                self.nx_swift.append(flag)
        self.nx_swift.extend(["-I$(SRCROOT)/Config/Dependencies/Modules",
                              "-F$(SRCROOT)/Config/Dependencies/Frameworks",
                              "-F$(SRCROOT)/Resources/Frameworks"])
        for arg in dict.fromkeys(self.xcc):
            self.nx_swift.extend(["-Xcc", arg])
        # An interface may request a library even when the original linker used
        # its object directly. Archive names must match that autolink identity.
        for interface in self.project.rglob("*.swiftinterface"):
            text = interface.read_text()
            for name in re.findall(r"-module-link-name\s+(\S+)", text):
                require(name in self.lib_names or name in self.framework_names,
                        f"Interface requires an unexported library: {name}")

    def config(self, info):
        target = self.settings["IPHONEOS_DEPLOYMENT_TARGET"]
        language = option_values(self.swift, "-swift-version")
        language = language[-1] if language else self.settings.get("SWIFT_VERSION", "5.0").split(".")[0]
        swift = ["-target", "arm64-apple-ios$(NXDeploymentTarget)", "-swift-version", language,
                 "-Xllvm", "-aarch64-use-tbi", "-Xfrontend", "-enable-objc-interop",
                 "-sdk", "$(SDKROOT)", "-resource-dir", "$(BSROOT)/swift",
                 "-module-cache-path", "$(BSROOT)/ModuleCache", "-parse-as-library", "-O"]
        config = {
            "NXProjectFormat": "NXAvixR2", "NXProjectScheme": "Application",
            "NXExecutable": "Hayase", "NXDisplayName": "Hayase", "NXOrganizationPrefix": "app",
            "NXBundleIdentifier": info["CFBundleIdentifier"], "NXDeploymentTarget": target,
            "NXBundleVersion": info["CFBundleVersion"], "NXBundleShortVersion": info["CFBundleShortVersionString"],
            "NXBundleInfo": info, "NXOutputPath": "$(CACHEROOT)/Payload/Hayase.app/Hayase",
            "NXSignMachOWithNyxianEntitlements": True,
            # Imports/autolink metadata and explicit exported links are complete.
            # Nyxian's C-only scanner must not invent extra package framework links.
            "NXLinkFrameworksAutomatically": False,
            "NXSwiftFlags": swift + self.nx_swift,
            "NXClangFlags": ["-target", "arm64-apple-ios$(NXDeploymentTarget)", "-isysroot", "$(SDKROOT)",
                             "-resource-dir", "$(BSROOT)/Include", "-L$(BSROOT)/lib", "-lclang_rt.ios", "-fmodules", "-fobjc-arc"],
            "NXLinkerFlags": self.nx_link,
        }
        (self.project / "Config").mkdir(exist_ok=True)
        for filename, data in (("Project.plist", config), ("Entitlements.plist", {"org.emexlabs.nyxian.get-task-allow": True})):
            (self.project / "Config" / filename).write_bytes(plistlib.dumps(data, sort_keys=False))
        return config


def validate_layout(project, config, sources):
    actual = {p.relative_to(project) for p in project.rglob("*") if p.is_file() and p.suffix in CODE_SUFFIXES
              and p.relative_to(project).parts[0] not in {"Config", "Resources"}}
    require(actual == set(sources), "Nyxian source discovery differs from the actual Hayase target")
    require(not list(project.rglob("*.o")), "Raw objects would be deleted by Nyxian.clean()")
    require(not any(p.is_symlink() for p in project.rglob("*")), "Archive contains unresolved symlinks")
    require(config["NXProjectFormat"] == "NXAvixR2" and config["NXProjectScheme"] == "Application", "Wrong Nyxian project type")
    for key in ("NXSwiftFlags", "NXClangFlags", "NXLinkerFlags"):
        for arg in config[key]:
            require(not re.search(r"(?:^|=|,-?|-[IFL])/(?:Users|Volumes|Applications|private|tmp)/", arg),
                    f"CI path leaked into {key}: {arg}")
    for name in RESOURCE_REQUIREMENTS:
        require((project / "Resources" / name).exists(), f"Missing resource {name}")


def smoke_test(exporter, config, output):
    """Compile/link from relocated inputs, without SPM or Xcode project context."""
    sdk = run("xcrun", "--sdk", "iphoneos", "--show-sdk-path")
    target_info = json.loads(run("xcrun", "swiftc", "-print-target-info"))
    swift_resources = target_info["paths"]["runtimeResourcePath"]
    variables = {"SRCROOT": str(exporter.project), "SDKROOT": sdk,
                 "NXDeploymentTarget": config["NXDeploymentTarget"]}
    def expand(arg):
        for name, value in variables.items():
            arg = arg.replace("$(" + name + ")", value)
        return arg
    flags = [expand(arg) for arg in config["NXSwiftFlags"]]
    flags[flags.index("$(BSROOT)/swift")] = swift_resources
    flags[flags.index("$(BSROOT)/ModuleCache")] = str(output / "smoke-module-cache")
    args = ["xcrun", "swiftc", *flags, "-module-name", "Hayase"]
    args.extend(str(exporter.project / path) for path in exporter.source_paths)
    for arg in config["NXLinkerFlags"]:
        args.extend(["-Xlinker", expand(arg)])
    args.extend(["-o", str(output / "Hayase-export-smoke")])
    with (output / "export-smoke.log").open("w") as log:
        subprocess.run(args, check=True, stdout=log, stderr=subprocess.STDOUT)


def zip_project(project, archive):
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as zf:
        for path in sorted(project.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(project.parent).as_posix())
    with zipfile.ZipFile(archive) as zf:
        require({name.split("/")[0] for name in zf.namelist()} == {"Hayase"}, "ZIP must have exactly one project directory")
        require("Hayase/Config/Project.plist" in zf.namelist(), "ZIP has no Nyxian config")
        require(zf.testzip() is None, "ZIP CRC verification failed")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("repo", "derived-data", "packages", "build-log", "settings", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    options = parser.parse_args()
    settings = json.loads(options.settings.read_text())
    settings = [s["buildSettings"] for s in settings if s["target"] == "Hayase"]
    require(len(settings) == 1, "Expected exactly one Hayase target settings record")
    require(settings[0]["PLATFORM_NAME"] == "iphoneos", "Simulator build cannot be exported to Nyxian")
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nyxian-stage-", dir=output) as temporary:
        project = Path(temporary) / "Hayase"
        exporter = Exporter(options.repo.resolve(), options.derived_data.resolve(), options.packages.resolve(),
                            settings[0], options.build_log.read_text(), project)
        info = exporter.sources_and_resources()
        exporter.archive_objects()
        exporter.frameworks_and_link_flags()
        exporter.import_metadata()
        config = exporter.config(info)
        validate_layout(project, config, exporter.source_paths)
        smoke_test(exporter, config, output)
        resolved = options.repo / "Hayase.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        require(resolved.is_file(), "Missing resolved dependency lockfile")
        copy_tree(resolved, project / "Config/Package.resolved")
        for path in options.repo.iterdir():
            if path.is_file() and re.search(r"license|copying|notice", path.name, re.I):
                copy_tree(path, project / "Config/Licenses" / path.name)
        copy_tree(options.repo / "docs/nyxian-export.md", project / "Config/README.md")
        report = {
            "hayaseRevision": run("git", "-C", options.repo, "rev-parse", "HEAD"),
            "nyxianContractRevision": NYXIAN_REVISION,
            "xcode": run("xcodebuild", "-version"), "swift": run("xcrun", "swiftc", "--version"),
            "sdkVersion": run("xcrun", "--sdk", "iphoneos", "--show-sdk-version"),
            "deploymentTarget": config["NXDeploymentTarget"], "architecture": "arm64",
            "sourceCount": len(exporter.source_paths), "libraries": sorted(exporter.lib_names),
            "frameworks": sorted(exporter.framework_names), "packages": json.loads(resolved.read_text()),
            "torrentClientRevision": run("git", "-C", options.repo / ".build/webtorrent-backend/torrent-client", "rev-parse", "HEAD"),
            "checks": {"originalXcodeBuild": "passed", "nyxianLayout": "passed", "relocatedCompileAndLink": "passed",
                       "onDeviceNyxianRun": "not performed"},
        }
        (project / "Config/export-report.json").write_text(json.dumps(report, indent=2) + "\n")
        archive = Path(temporary) / "Hayase-Nyxian-Source.zip"
        zip_project(project, archive)
        checksum = sha256(archive)
        report["archiveSHA256"] = checksum
        # Publish only after every check succeeds; no partially valid ZIP.
        archive.replace(output / archive.name)
        (output / (archive.name + ".sha256")).write_text(checksum + "  " + archive.name + "\n")
        (output / "export-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Validated Nyxian project: {output / archive.name}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"error: Nyxian export failed: {error}") from error
