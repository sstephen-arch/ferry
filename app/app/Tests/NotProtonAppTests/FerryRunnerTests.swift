import Foundation
import Testing

@testable import NotProtonApp

// Ferry runners: scratch directories only, nothing under the real support directory.

private enum FerryFixture {
    static let files: [String: Data] = [
        FerryRunner.loaderPath: Data("loader".utf8),
        "lib/wine/x86_64-windows/ntdll.dll": Data("ntdll x86_64".utf8),
        "lib/wine/i386-windows/ntdll.dll": Data("ntdll i386".utf8),
        "bin/wineserver": Data("wineserver".utf8),
        FerryRunner.unixNtdllPath: Data("ntdll.so with FERRY_DLLPATH_FIRST inside".utf8),
    ]

    static func sha(_ data: Data) throws -> String {
        let url = URL.temporaryDirectory.appending(path: "ferry-sha-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(Digest.sha256IfPresent(url))
    }

    // A runner folder like runner/package.sh writes: CrossOver/ + manifest.json
    static func make(in dir: URL, version: String = "26.3.0-ferry.9", flavor: String = "rosetta",
                     skipFile: String? = nil, tamper: String? = nil, manifestText: String? = nil) throws -> URL {
        let runner = dir.appending(path: "ferry-runner-\(version)-rosetta")
        var hashes: [String: String] = [:]
        for (path, data) in files {
            hashes[path] = try sha(data)
            guard path != skipFile else { continue }
            let url = runner.appending(path: "CrossOver/\(path)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (path == tamper ? Data("tampered".utf8) : data).write(to: url)
        }
        let manifest: [String: Any] = [
            "name": "Ferry", "version": version, "flavor": flavor, "wine_version": "11.0",
            "built_at": "2026-10-11T00:00:00Z", "git_commit": "test",
            "patches": [["name": "0001-test.patch", "sha256": "00"]],
            "files": hashes, "graphics": ["dxmt": true, "d3dmetal": false],
            "bridge": ["steam.exe": "aa"],
        ]
        let text = try manifestText.map { Data($0.utf8) } ?? JSONSerialization.data(withJSONObject: manifest)
        try text.write(to: runner.appending(path: FerryRunner.manifestName))
        return runner
    }
}

@Suite("Ferry runner manifest")
struct FerryManifestTests {

    @Test("A complete runner loads and every hash is checked")
    func loads() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir))
        #expect(runner.manifest.version == "26.3.0-ferry.9")
        #expect(runner.buildID == "ferry-26.3.0-ferry.9")
        #expect(runner.root.lastPathComponent == "CrossOver")
    }

    @Test("Bad JSON is refused as unreadable")
    func badJSON() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, manifestText: "{ not json")
        #expect {
            try FerryRunner.load(from: folder)
        } throws: { error in
            if case FerryRunner.LoadError.unreadable = error { return true }
            return false
        }
    }

    @Test("A folder without manifest.json is refused")
    func noManifest() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: FerryRunner.LoadError.noManifest) { try FerryRunner.load(from: dir) }
    }

    @Test("Only rosetta runners are accepted")
    func flavor() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, flavor: "fex")
        #expect(throws: FerryRunner.LoadError.unsupportedFlavor("fex")) { try FerryRunner.load(from: folder) }
    }

    @Test("A file the manifest lists but the runner lacks is refused")
    func missingFile() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, skipFile: "bin/wineserver")
        #expect(throws: FerryRunner.LoadError.missingFile("bin/wineserver")) { try FerryRunner.load(from: folder) }
    }

    @Test("A file whose hash differs from the manifest is refused")
    func hashMismatch() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, tamper: "lib/wine/x86_64-windows/ntdll.dll")
        #expect(throws: FerryRunner.LoadError.hashMismatch("lib/wine/x86_64-windows/ntdll.dll")) {
            try FerryRunner.load(from: folder)
        }
    }

    @Test("verify: false only decodes (used for already-installed runners)")
    func decodeOnly() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, tamper: "bin/wineserver")
        #expect(throws: Never.self) { try FerryRunner.load(from: folder, verify: false) }
    }
}

@Suite("Ferry runner hardening")
struct FerryHardeningTests {

    @Test("A version that is not 26.3.0-ferry.N is refused (it becomes a path component)")
    func badVersion() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, version: "../../tmp/evil")
        #expect(throws: FerryRunner.LoadError.invalidVersion("../../tmp/evil")) { try FerryRunner.load(from: folder) }
    }

    @Test("A manifest path that climbs out of the runner is refused")
    func traversal() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir)
        let manifestURL = folder.appending(path: FerryRunner.manifestName)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var files = try #require(json["files"] as? [String: String])
        files["../../outside"] = "00"
        json["files"] = files
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
        #expect(throws: FerryRunner.LoadError.unsafePath("../../outside")) { try FerryRunner.load(from: folder) }
    }

    @Test("A runner whose CrossOver/ is a symlink (e.g. to a real CrossOver) is refused")
    func symlinkedRoot() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = try FerryFixture.make(in: dir)
        let fake = dir.appending(path: "fake")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fake.appending(path: "CrossOver"),
                                                   withDestinationURL: real.appending(path: "CrossOver"))
        try FileManager.default.copyItem(at: real.appending(path: FerryRunner.manifestName),
                                         to: fake.appending(path: FerryRunner.manifestName))
        #expect {
            try FerryRunner.load(from: fake)
        } throws: { error in
            if case FerryRunner.LoadError.unsafePath = error { return true }
            return false
        }
    }

    @Test("A tree whose ntdll.so lacks the Ferry patch cannot pass as a Ferry runner")
    func notFerry() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir)
        let so = folder.appending(path: "CrossOver/\(FerryRunner.unixNtdllPath)")
        let plain = Data("a CrossOver ntdll.so".utf8)
        try plain.write(to: so)
        let manifestURL = folder.appending(path: FerryRunner.manifestName)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var files = try #require(json["files"] as? [String: String])
        files[FerryRunner.unixNtdllPath] = try FerryFixture.sha(plain)
        json["files"] = files
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
        #expect(throws: FerryRunner.LoadError.notFerry) { try FerryRunner.load(from: folder) }
    }
}

@Suite("Ferry runner build")
struct FerryBuildTests {

    @Test("A Ferry build is source-patched with empty binary-patch tables")
    func policy() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir))
        let build = runner.build
        #expect(build.isFerry)
        #expect(build.cleanNtdll.isEmpty && build.patchedNtdll.isEmpty)
        #expect(build.ntdllPolicy == .sourcePatched(expected: runner.expectedNtdll))
        #expect(runner.expectedNtdll.count == 2)
        #expect(build.loaderSHA256 == runner.manifest.files[FerryRunner.loaderPath])
        #expect(build.tools.map(\.name) == ["notproton-ferry-26.3.0-ferry.9"])
        #expect(NtdllPatcher.patches(for: build).isEmpty)
    }

    @Test("Pinned CrossOver builds keep the binary-patch policy")
    func pinnedUnchanged() {
        #expect(SupportedRunners.pinned.allSatisfy { $0.ntdllPolicy == .binaryPatch && !$0.isFerry })
    }

    @Test("A registered Ferry build is found by id, and is gone once unregistered")
    func registry() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir, version: "26.3.0-ferry.901"))
        FerryRunners.register(runner)
        defer { FerryRunners.unregister(directory: runner.directory) }
        #expect(SupportedRunners.build(id: runner.buildID)?.isFerry == true)
        FerryRunners.unregister(directory: runner.directory)
        #expect(SupportedRunners.build(id: runner.buildID) == nil)
    }

    @Test("verifyNtdll accepts the shipped copies and refuses others")
    func verifyNtdll() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir))
        #expect(throws: Never.self) { try FerryRunner.verifyNtdll(runner.expectedNtdll, root: runner.root) }
        try Data("other".utf8).write(to: runner.root.appending(path: "lib/wine/i386-windows/ntdll.dll"))
        #expect(throws: StepFailure.self) { try FerryRunner.verifyNtdll(runner.expectedNtdll, root: runner.root) }
    }
}

@Suite("Ferry runner setup")
struct FerrySetupTests {

    final class Calls: @unchecked Sendable {
        var licenseChecked = 0
        var binaryStaged = 0
    }

    // The clone exists under a scratch runners dir; prepare must neither licence-check nor
    // binary-patch a Ferry build.
    @Test("prepare never licence-checks or binary-patches a Ferry build")
    func prepareFerry() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir, version: "26.3.0-ferry.902"))
        FerryRunners.register(runner)
        defer { FerryRunners.unregister(directory: runner.directory) }
        let build = runner.build
        let runners = dir.appending(path: "runners")
        let target = SupportPaths.runnerRoot(forBuild: build.id, runners: runners)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: runner.root, to: target.appending(path: "CrossOver"))
        try FileManager.default.copyItem(at: runner.manifestURL, to: target.appending(path: FerryRunner.manifestName))

        let calls = Calls()
        let outcome = try RunnerSetup.prepare(
            build,
            runners: runners,
            bridge: runners.appending(path: "bridge"),
            toolList: runners.appending(path: "tools"),
            compatTools: runners.appending(path: "compatibilitytools.d"),
            runScript: {
                let script = runners.appending(path: "payload-run")
                try Data("#!/bin/sh\n".utf8).write(to: script)
                return script
            },
            license: { _ in
                calls.licenseChecked += 1
                return CrossOverLicense.Status(licensed: false, detail: "no", diagnostic: "no")
            },
            verify: { _, _ in },
            patch: { _, _, _ in RunnerPatcher.Outcome() }
        )
        #expect(calls.licenseChecked == 0)
        #expect(outcome.staged.isEmpty)
    }

    @Test("An unlicensed CrossOver build is still refused (upstream behaviour kept)")
    func crossOverStillChecked() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let build = try #require(SupportedRunners.pinned.first)
        let runners = dir.appending(path: "runners")
        let cloned = SupportPaths.clonedRoot(forBuild: build.id, runners: runners)
        try FileManager.default.createDirectory(at: cloned.appending(path: "lib/wine/x86_64-unix"), withIntermediateDirectories: true)
        try Data("loader".utf8).write(to: cloned.appending(path: "lib/wine/x86_64-unix/wine"))

        let calls = Calls()
        #expect(throws: StepFailure.self) {
            try RunnerSetup.prepare(
                build,
                runners: runners,
                bridge: runners.appending(path: "bridge"),
                toolList: runners.appending(path: "tools"),
                compatTools: runners.appending(path: "compatibilitytools.d"),
                runScript: { runners.appending(path: "payload-run") },
                license: { _ in
                    calls.licenseChecked += 1
                    return CrossOverLicense.Status(licensed: false, detail: "not activated", diagnostic: "test")
                },
                verify: { _, _ in },
                stage: { _, _, _ in calls.binaryStaged += 1; return [] },
                patch: { _, _, _ in RunnerPatcher.Outcome() }
            )
        }
        #expect(calls.licenseChecked == 1)
        #expect(calls.binaryStaged == 0)
    }

    @Test("A Ferry install is never licence-checked by run(); a CrossOver one is")
    func runLicenceGate() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir, version: "26.3.0-ferry.903"))
        let ferry = CrossOverInstall(bundle: runner.directory, releaseVersion: runner.manifest.version,
                                     support: .supported(runner.build), isManual: true, ferry: runner)
        #expect(ferry.isFerry)
        #expect(ferry.crossOverRoot == runner.root)
        let crossOver = CrossOverInstall(bundle: dir.appending(path: "CrossOver.app"), releaseVersion: "26.3",
                                         support: .unreadable)
        #expect(!crossOver.isFerry)
    }
}

@Suite("Ferry bridge payload")
struct FerryBridgePayloadTests {

    @Test("A Rosetta-only payload without the arm64 unix half is complete")
    func arm64Optional() throws {
        let dir = try scratchDirectory("ferry-bridge")
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["steam.exe", "x86_64-windows-lsteamclient.dll", "x86_64-unix-lsteamclient.so",
                     "i386-windows-lsteamclient.dll"] {
            try Data(name.utf8).write(to: dir.appending(path: name))
        }
        let located = try BridgePayload.locate(root: dir)
        #expect(located.sources.count == 4)
    }

    @Test("A required bridge file is still required")
    func requiredStillRequired() throws {
        let dir = try scratchDirectory("ferry-bridge")
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["steam.exe", "x86_64-unix-lsteamclient.so", "i386-windows-lsteamclient.dll"] {
            try Data(name.utf8).write(to: dir.appending(path: name))
        }
        #expect(throws: StepFailure.self) { try BridgePayload.locate(root: dir) }
    }
}

@Suite("Ferry real runner")
struct FerryRealRunnerTests {

    // Run with FERRY_REAL_RUNNER=<dist/ferry-runner-...-rosetta> to check the actual build
    // passes every hardening check (marker, hashes, containment, version).
    @Test("The packaged runner in dist loads with full verification",
          .enabled(if: ProcessInfo.processInfo.environment["FERRY_REAL_RUNNER"] != nil))
    func realRunner() throws {
        let path = try #require(ProcessInfo.processInfo.environment["FERRY_REAL_RUNNER"])
        let runner = try FerryRunner.load(from: URL(filePath: path, directoryHint: .isDirectory))
        #expect(runner.build.isFerry)
        #expect(runner.manifest.files["share/ferry/backend.sh"] != nil)
    }
}

@Suite("Ferry signing")
struct FerrySigningTests {

    // The failure seen on the owner's Steam.app: Finder metadata on the bundle folder made
    // `codesign` refuse the executable inside it.
    @Test("A bundle with Finder metadata on its folder can still be ad-hoc signed")
    func findInfoOnBundle() throws {
        let dir = try scratchDirectory("ferry-sign")
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appending(path: "Fake.app")
        let macos = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let exe = macos.appending(path: "fake")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: exe)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleExecutable</key><string>fake</string>
        <key>CFBundleIdentifier</key><string>local.ferry.signtest</string></dict></plist>
        """.write(to: app.appending(path: "Contents/Info.plist"), atomically: true, encoding: .utf8)
        let finderInfo = "0000000000000000001000000000000000000000000000000000000000000000"  // the bytes on the owner's Steam.app
        _ = try Shell.run("/usr/bin/xattr", ["-wx", "com.apple.FinderInfo", finderInfo, app.path(percentEncoded: false)])
        let before = try Shell.run("/usr/bin/codesign", ["-f", "-s", "-", exe.path(percentEncoded: false)])
        #expect(!before.succeeded)  // the bug: plain codesign refuses
        #expect(throws: Never.self) { try SteamInstaller.adHocSign(exe) }
        #expect(throws: Never.self) { try SteamInstaller.adHocSign(app) }
    }
}

@Suite("Ferry loader entitlements")
struct FerryLoaderEntitlementTests {

    // Set Up failed on the owner's Mac: "x86_64-unix/wine carries no entitlements to extend".
    // An unsigned loader has no hardened runtime, so it needs no dyld entitlement.
    @Test("An unsigned loader is not hardened; a runtime-signed one is")
    func hardenedRuntime() throws {
        let dir = try scratchDirectory("ferry-loader")
        defer { try? FileManager.default.removeItem(at: dir) }
        let loader = dir.appending(path: "wine")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: loader)
        _ = try Shell.run("/usr/bin/codesign", ["--remove-signature", loader.path(percentEncoded: false)])
        #expect(!RunnerPatcher.usesHardenedRuntime(loader))
        _ = try Shell.run("/usr/bin/codesign", ["-f", "-s", "-", "--options", "runtime", loader.path(percentEncoded: false)])
        #expect(RunnerPatcher.usesHardenedRuntime(loader))
    }
}

// Fixes from the 11 Oct full-code review (local models, checked by DeepSeek).
@Suite("Ferry review fixes")
struct FerryReviewFixTests {

    // A runner root with an unsigned x86_64 loader and the three Rosetta bridge builtins.
    private static func rosettaRoot(in dir: URL, arm64: Bool = false) throws -> URL {
        let root = dir.appending(path: "root")
        var arches = ["x86_64-unix"]
        if arm64 { arches.append("aarch64-unix") }
        for arch in arches {
            let loader = root.appending(path: "lib/wine/\(arch)/wine")
            try FileManager.default.createDirectory(at: loader.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: loader)
            _ = try Shell.run("/usr/bin/codesign", ["--remove-signature", loader.path(percentEncoded: false)])
        }
        for (arch, name) in [("i386-windows", "lsteamclient.dll"), ("x86_64-windows", "lsteamclient.dll"),
                             ("x86_64-unix", "lsteamclient.so")] {
            let url = root.appending(path: "lib/wine/\(arch)/\(name)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: url)
        }
        return root
    }

    @Test("verify does not call an unsigned Ferry loader 'missing the dyld entitlement'")
    func verifyUnsignedLoader() throws {
        let dir = try scratchDirectory("ferry-verify")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try Self.rosettaRoot(in: dir)
        let build = try FerryRunner.load(from: FerryFixture.make(in: dir)).build
        let bridge = dir.appending(path: "empty-bridge")
        #expect(RunnerPatcher.verify(build: build, root: root, bridge: bridge) == [])
    }

    @Test("A FEX build is refused before anything is written")
    func fexRefusedCleanly() throws {
        let dir = try scratchDirectory("ferry-fex")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try Self.rosettaRoot(in: dir, arm64: true)
        let bridge = dir.appending(path: "bridge")
        for (arch, name) in [("i386-windows", "lsteamclient.dll"), ("x86_64-windows", "lsteamclient.dll"),
                             ("x86_64-unix", "lsteamclient.so")] {
            let url = bridge.appending(path: "\(arch)/\(name)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("bridge \(name)".utf8).write(to: url)
        }
        let fex = try #require(SupportedRunners.build(id: "27.0.0.40921-fex"))
        #expect {
            try RunnerPatcher.install(build: fex, root: root, bridge: bridge)
        } throws: { error in
            (error as? StepFailure)?.detail.contains("FEX") == true
        }
        // nothing patched or copied: the builtin is still the original
        let so = root.appending(path: "lib/wine/x86_64-unix/lsteamclient.so")
        #expect(try Data(contentsOf: so) == Data("lsteamclient.so".utf8))
    }

    @Test("verifyClone checks a Ferry clone's Windows ntdll")
    func verifyCloneFerryNtdll() throws {
        let dir = try scratchDirectory("ferry-clone")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir))
        #expect(throws: Never.self) { try RunnerInstaller.verifyClone(build: runner.build, root: runner.root) }
        try Data("other".utf8).write(to: runner.root.appending(path: "lib/wine/x86_64-windows/ntdll.dll"))
        #expect(throws: StepFailure.self) { try RunnerInstaller.verifyClone(build: runner.build, root: runner.root) }
    }

    @Test("A CrossOver app whose loader matches a Ferry build is not taken for that build")
    func crossOverNotMatchedToFerry() throws {
        let dir = try scratchDirectory("ferry-inspect")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = try FerryRunner.load(from: FerryFixture.make(in: dir, version: "26.3.0-ferry.904"))
        FerryRunners.register(runner)
        defer { FerryRunners.unregister(directory: runner.directory) }
        let bundle = dir.appending(path: "CrossOver.app")
        let loader = CrossOverSource.unixLoader(inBundle: bundle)
        try FileManager.default.createDirectory(at: loader.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: runner.root.appending(path: FerryRunner.loaderPath), to: loader)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "26.3.0"],
                                                       format: .xml, options: 0)
        try plist.write(to: bundle.appending(path: "Contents/Info.plist"))
        #expect(CrossOverSource.inspect(bundle: bundle).support == .unsupportedBuild("26.3.0"))
    }

    @Test("Only 26.3.0-ferry.N versions load")
    func otherBaseVersion() throws {
        let dir = try scratchDirectory("ferry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try FerryFixture.make(in: dir, version: "99.99.99-ferry.1")
        #expect(throws: FerryRunner.LoadError.invalidVersion("99.99.99-ferry.1")) { try FerryRunner.load(from: folder) }
    }

    @Test("A file that can't be looked up fails closed, not as missing")
    func unreadableLookup() throws {
        let dir = try scratchDirectory("ferry")
        let folder = try FerryFixture.make(in: dir)
        let lib = folder.appending(path: "CrossOver/lib").path(percentEncoded: false)
        _ = try Shell.run("/bin/chmod", ["000", lib])
        defer {
            _ = try? Shell.run("/bin/chmod", ["755", lib])
            try? FileManager.default.removeItem(at: dir)
        }
        #expect {
            try FerryRunner.load(from: folder)
        } throws: { error in
            if case FerryRunner.LoadError.unsafePath = error { return true }
            return false
        }
    }
}

// The run script's graphics-backend block, run for real under /bin/sh (set -e, as in the script).
@Suite("Ferry run script backend block")
struct FerryBackendBlockTests {

    private static func block() throws -> String {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)
        let start = try #require(lines.firstIndex { $0.hasPrefix("if [ -f \"$CX_ROOT/share/ferry/backend.sh\" ]; then") })
        let end = try #require(lines[start...].firstIndex { $0 == "fi" })
        return lines[start...end].joined(separator: "\n")
    }

    // Runs the block with a backend.sh that exports a variable and warns on stderr.
    private static func run(log: String, in dir: URL) throws -> CommandResult {
        let root = dir.appending(path: "CrossOver")
        let backend = root.appending(path: "share/ferry/backend.sh")
        try FileManager.default.createDirectory(at: backend.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "FERRY_PROBE=1; export FERRY_PROBE; echo backend-warning >&2\n".write(to: backend, atomically: true, encoding: .utf8)
        let program = "set -e\nCX_ROOT=\"$1\"\nlog=\"$2\"\n\(try block())\necho \"FERRY_PROBE=$FERRY_PROBE\"\n"
        return try Shell.run("/bin/sh", ["-c", program, "sh", root.path(percentEncoded: false), log])
    }

    @Test("A log that can't be opened doesn't stop the launch")
    func unwritableLog() throws {
        let dir = try scratchDirectory("ferry-backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try Self.run(log: dir.appending(path: "missing/notproton-run.log").path(percentEncoded: false), in: dir)
        #expect(result.succeeded)
        #expect(result.stdout.contains("FERRY_PROBE=1"))
    }

    // Runs the block for <exe> with a backend.sh that echoes what it was given. helperSays: what a
    // stand-in `appinfo --graphics` prints (nil: no helper installed).
    private static func backend(_ launchOption: String?, helperSays: String? = nil, exe: String = "Game.exe",
                                in dir: URL) throws -> String {
        let root = dir.appending(path: "CrossOver")
        let script = root.appending(path: "share/ferry/backend.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "echo \"backend=$CX_GRAPHICS_BACKEND avx=$ROSETTA_ADVERTISE_AVX\"\n".write(to: script, atomically: true, encoding: .utf8)
        let home = dir.appending(path: "home")
        let helper = home.appending(path: "Library/Application Support/notproton/appinfo")
        try? FileManager.default.removeItem(at: helper)
        if let helperSays {
            try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n[ \"$1\" = --graphics ] && echo '\(helperSays)'\n".write(to: helper, atomically: true, encoding: .utf8)
            _ = try Shell.run("/bin/chmod", ["+x", helper.path(percentEncoded: false)])
        }
        let set = launchOption.map { "CX_GRAPHICS_BACKEND=\($0); export CX_GRAPHICS_BACKEND\n" } ?? "unset CX_GRAPHICS_BACKEND\n"
        let log = dir.appending(path: "run.log").path(percentEncoded: false)
        let program = "set -e\n\(set)unset ROSETTA_ADVERTISE_AVX\nCX_ROOT=\"$1\"\nHOME=\"$2\"\nlog=\"$3\"\nshift 3\n\(try block())\n"
        return try Shell.run("/bin/sh", ["-c", program, "sh", root.path(percentEncoded: false),
                                         home.path(percentEncoded: false), log, exe]).stdout
    }

    @Test("A launch option picks the backend; otherwise D3DMetal when the .exe doesn't tell")
    func launchOptionAndDefault() throws {
        let dir = try scratchDirectory("ferry-backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try Self.backend(nil, in: dir).contains("backend=d3dmetal"))
        #expect(try Self.backend("dxmt", helperSays: "wined3d imports d3d9.dll", in: dir).contains("backend=dxmt"))
        #expect(try Self.backend("wined3d", in: dir).contains("backend=wined3d"))
    }

    @Test("Without a launch option the .exe's imports pick the backend, and AVX is reported")
    func autoDetected() throws {
        let dir = try scratchDirectory("ferry-backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try Self.backend(nil, helperSays: "wined3d .NET (XNA/FNA)", in: dir).contains("backend=wined3d avx=1"))
        #expect(try Self.backend(nil, helperSays: "dxmt imports d3d10.dll", in: dir).contains("backend=dxmt"))
        // the choice and its reason land in the game's log
        let log = try String(contentsOf: dir.appending(path: "run.log"), encoding: .utf8)
        #expect(log.contains("graphics: dxmt imports d3d10.dll (auto)"))
        // nonsense from the helper, or a non-.exe target, falls back to D3DMetal
        #expect(try Self.backend(nil, helperSays: "vulkan whatever", in: dir).contains("backend=d3dmetal"))
        #expect(try Self.backend(nil, helperSays: "wined3d imports d3d9.dll", exe: "notes.txt", in: dir).contains("backend=d3dmetal"))
    }

    @Test("backend.sh warnings go into the game's log")
    func warningsLogged() throws {
        let dir = try scratchDirectory("ferry-backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appending(path: "notproton-run.log")
        let result = try Self.run(log: log.path(percentEncoded: false), in: dir)
        #expect(result.succeeded)
        #expect(try String(contentsOf: log, encoding: .utf8).contains("backend-warning"))
    }
}

// A fresh install unpacks the runner shipped inside Ferry.app.
@Suite("Ferry bundled runner")
struct FerryBundledRunnerTests {

    private static func archive(_ runner: URL, in dir: URL) throws -> URL {
        let out = dir.appending(path: "ferry-runner.tar.gz")
        let tar = try Shell.run("/usr/bin/tar", ["-czf", out.path(percentEncoded: false), "-C",
                                                 runner.deletingLastPathComponent().path(percentEncoded: false),
                                                 runner.lastPathComponent])
        #expect(tar.succeeded)
        return out
    }

    private static func defaults() -> UserDefaults {
        let name = "ferry-bundled-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("It is unpacked once, verified and offered like a picked runner")
    func unpacksOnce() throws {
        let dir = try scratchDirectory("ferry-bundled")
        defer { try? FileManager.default.removeItem(at: dir) }
        let tar = try Self.archive(FerryFixture.make(in: dir.appending(path: "src"), version: "26.3.0-ferry.905"), in: dir)
        let root = dir.appending(path: "bundled-runner")
        let store = Self.defaults()

        let target = try #require(try BundledFerryRunner.ensure(archive: tar, root: root, defaults: store))
        defer { FerryRunners.unregister(directory: target) }
        #expect(target.lastPathComponent == "ferry-runner-26.3.0-ferry.905-rosetta")
        #expect(try FerryRunner.load(from: target).manifest.version == "26.3.0-ferry.905")
        #expect(FerryRunners.manualDirectories(store).contains { CrossOverSource.same($0, target) })

        // a second launch reuses it instead of unpacking again
        let marker = target.appending(path: "kept")
        try Data().write(to: marker)
        _ = try BundledFerryRunner.ensure(archive: tar, root: root, defaults: store)
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test("A runner that fails its manifest is refused and leaves nothing behind")
    func tamperedRefused() throws {
        let dir = try scratchDirectory("ferry-bundled")
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = try FerryFixture.make(in: dir.appending(path: "src"), version: "26.3.0-ferry.906",
                                        tamper: "bin/wineserver")
        let tar = try Self.archive(src, in: dir)
        let root = dir.appending(path: "bundled-runner")
        let store = Self.defaults()

        #expect(throws: FerryRunner.LoadError.hashMismatch("bin/wineserver")) {
            try BundledFerryRunner.ensure(archive: tar, root: root, defaults: store)
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []).isEmpty)
        #expect(FerryRunners.manualDirectories(store).isEmpty)
    }

    @Test("A newer bundled runner replaces the older one")
    func newerReplacesOlder() throws {
        let dir = try scratchDirectory("ferry-bundled")
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "bundled-runner")
        let store = Self.defaults()
        let old = try #require(try BundledFerryRunner.ensure(
            archive: Self.archive(FerryFixture.make(in: dir.appending(path: "a"), version: "26.3.0-ferry.907"), in: dir.appending(path: "a")),
            root: root, defaults: store))
        let new = try #require(try BundledFerryRunner.ensure(
            archive: Self.archive(FerryFixture.make(in: dir.appending(path: "b"), version: "26.3.0-ferry.908"), in: dir.appending(path: "b")),
            root: root, defaults: store))
        defer { FerryRunners.unregister(directory: new) }
        #expect(!FileManager.default.fileExists(atPath: old.path(percentEncoded: false)))
        #expect(FerryRunners.manualDirectories(store).map(\.lastPathComponent) == [new.lastPathComponent])
    }
}
