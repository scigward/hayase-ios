# Nyxian source export

Run the **Export Nyxian Source** (`hayase_nyxian_source`) workflow manually in Codemagic. It builds Hayase for a physical iOS device and converts that successful build into a self-contained, editable Nyxian project. The normal IPA workflow is unchanged.

Artifacts are written to `build/nyxian-export/`:

- `Hayase-Nyxian-Source.zip`: the project to import in Nyxian.
- `Hayase-Nyxian-Source.zip.sha256`: the archive checksum.
- `export-report.json`: the source revision, dependency snapshot and export validation results.

The workflow uses `scripts/export_nyxian_source.sh`. A failed build or incomplete dependency export fails the workflow; it does not publish a partial project as a successful export.

No signing secrets or new Codemagic environment groups are required. The export uses the workflow's selected Xcode, the existing WebTorrent/GeoIP builders, and the exact resolved package revisions; their versions are recorded in the report. The script can also be run with `bash scripts/export_nyxian_source.sh` on a Mac with Xcode, XcodeGen, Node and Python 3.9 or newer. `NYXIAN_PACKAGES_DIR` can override the package cache location.

## Import and run

1. Download the ZIP artifact from Codemagic and transfer it to Files on the iPhone or iPad.
2. Finish Nyxian's SDK/toolchain bootstrap and configure its signing setup. These are Nyxian prerequisites, not files supplied by this export.
3. Use the import button on Nyxian's Projects screen and select `Hayase-Nyxian-Source.zip`.
4. Open Hayase and build/run it in Nyxian. No Xcode project generation, package resolution or resource compilation is required on the device.

The export includes editable **app target** source files, preserving their original relative paths. Dependency binaries, import modules and resources are frozen at the revisions used for that Codemagic build. Editing Hayase's Swift source is supported; changing package versions, package sources, asset catalogs, storyboards or other compiled resources requires a new Codemagic export.

## Why this is not a renamed final-source archive

The compatibility contract was reviewed against Nyxian commit [`350dd8dbeb796bc0ff5bc91ef770f1a2994432e7`](https://github.com/emexlab/Nyxian/tree/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7), not inferred from its README:

- Its [project importer](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Nyxian/UI/ContentView.swift#L357-L397) opens ZIP archives, extracts them, and moves the first non-hidden top-level entry into Projects. The export therefore has exactly one top-level project directory. A `.tar.gz` is not an importable project artifact.
- [NXProject](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Nyxian/LindChain/IDEFoundation/NXProject.m#L141-L157) reads `Config/Project.plist`, not `.xcodeproj`, `.xcworkspace`, `project.yml` or `Package.swift`. The generated configuration uses the actual [`NXAvixR2` format and `Application` scheme](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Nyxian/LindChain/IDEFoundation/NXType.h#L26-L49).
- [NXPhaseEngine](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Nyxian/LindChain/IDEBuilder/NXPhaseEngine.m#L28-L78) recursively gathers every `.swift`, `.c`, `.cpp`, `.m` and `.mm` file outside `Config/` and `Resources/`. Copying a whole checkout would accidentally compile package manifests, tests and vendor implementations into the application. Only the real Hayase target's source files are placed in the scanned tree.
- [NXBuilder.prepare](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Nyxian/LindChain/IDEBuilder/NXBuilder.swift#L146-L160) copies `Resources/` directly into the `.app` and writes `NXBundleInfo` as its `Info.plist`. The export starts from the built app's resources, preserving compiled storyboards, asset catalogs, models, package resource bundles, WebTorrent backend files and GeoIP data. It excludes the old app executable, signing metadata and provisioning profile.
- [Configuration variables](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Nyxian/LindChain/IDEFoundation/NXProject.m#L147-L156) include `$(SRCROOT)`, `$(SDKROOT)`, `$(BSROOT)` and `$(CACHEROOT)`. Exported flags use those variables rather than Codemagic's absolute checkout/cache paths. Swift compiler flags preserve Hayase's language version and target settings and use Nyxian's own SDK/toolchain.
- [The phase runner](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Frameworks/MobileDevelopmentKit/PhaseEngine/MDKPhaseEngine.m#L118-L138) appends `NXLinkerFlags` to the final linker job. Those are raw linker arguments, distinct from `NXSwiftFlags` and `NXClangFlags`.
- [Nyxian's Swift driver adapter](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Frameworks/CoreCompiler/Tools/CCDriver.cpp#L662-L781) copies generated job arguments without running Swift's file-list preparation. Swift's legacy driver defaults to temporary file lists above 128 inputs, so the export sets `-driver-filelist-threshold 2147483647` to keep source and object paths inline. This is required for large targets such as Hayase; a normal macOS `swiftc` smoke test alone would not reveal Nyxian's unpopulated lists.
- The exported app uses `-O -whole-module-optimization -num-threads 0`. This keeps every Swift file editable, but produces one app object rather than one per source file. It reduces the oversized argument list that triggers the [reviewed Nyxian linker's storage-lifetime defect](https://github.com/emexlab/Nyxian/blob/350dd8dbeb796bc0ff5bc91ef770f1a2994432e7/Frameworks/CoreCompiler/Tools/Linker/CCLinker.cpp#L56-L60). Zero is intentional: [the legacy driver treats every positive thread count as multi-threaded](https://github.com/swiftlang/swift/blob/swift-6.4.0-RELEASE/include/swift/Driver/Driver.h#L130-L133) and produces per-input objects again. This is an export-side workaround, not a Nyxian patch or proof that the defect caused a particular device failure. It does not remove compiler options, architecture flags or dependency links.

Precompiled dependencies and their import metadata live under `Config/Dependencies`, outside Nyxian's source scan. Runtime frameworks remain under `Resources/Frameworks` so they are copied into the rebuilt app. Their identities and directory structure are retained; the exporter does not flatten unrelated frameworks, libraries and module files into one collision-prone folder.

The exporter keeps unstripped framework headers/modules separately from Xcode's stripped embedded copies. Swift dependencies use textual interfaces rather than compiler-specific serialized modules. Package objects are archived as named static libraries because Nyxian deletes raw `.o` files while cleaning. Only active packages in `Package.resolved` are included, not unrelated checkouts left in the shared cache. The normal Hayase bridging header is currently empty; exporting intentionally stops if future changes add ObjC imports rather than silently losing them during the distribution build.

No Apple SDK, signing credentials, provisioning profiles or Nyxian implementation source is redistributed. Hayase source and dependency license information remain part of the export.

## Validation and limits

The export workflow builds the original app first, validates the generated archive's layout and portable dependency paths, and runs a macOS compiler/linker smoke test using the exported app sources and dependencies. The smoke test substitutes the Mac's device SDK/toolchain for Nyxian's toolchain variables; it checks the export's build inputs rather than merely checking that a ZIP exists.

Before the smoke compilation, the workflow inspects `swiftc -driver-print-jobs` output. Export stops if the app is not compiled in one job to one object, if a source is omitted, or if generated temporary file lists/primary-file jobs return. `export-driver-jobs.log` is included in the workflow artifacts, and `export-report.json` records the host driver plan. Its argument count describes the host job, not Nyxian's additional Swift-to-Clang linker adaptation. Dependency/runtime flags still contribute to Nyxian's final argument count, so single-object compilation is not a general repair for its linker.

App source edits rebuild the whole app module in Nyxian; this can use more peak memory than compiling individual files. The normal IPA workflow, frozen dependency binaries and app behavior are unchanged. Re-export and import the new ZIP to use this configuration; previously downloaded archives retain their old flags.

This does **not** substitute for executing the archive in Nyxian. Nyxian uses its own Swift compiler, SDK, linker and guest runtime. Compiler-version compatibility, signing and runtime behavior still need confirmation on the actual device. Local development on Windows cannot run that iOS validation, and the workflow must not be described as on-device tested until that test has happened. The pinned Nyxian source describes the reviewed contract; future Nyxian format/toolchain changes may require updating the exporter.
