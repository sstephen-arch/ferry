// Ferry runners: Wine builds made by this repo's runner/ scripts, with no CrossOver involved.
// A runner directory holds CrossOver/ (the runner root, named so the run script's
// runners/crossover-<build>/CrossOver lookup keeps working) and manifest.json written by
// runner/package.sh. Every hash in the manifest is checked before a runner is first trusted.
// Ferry builds steamclient redirection into ntdll's source, so there is nothing to patch.

import Foundation

struct FerryManifest: Codable, Sendable, Equatable {
    struct Patch: Codable, Sendable, Equatable {
        let name: String
        let sha256: String
    }

    struct Graphics: Codable, Sendable, Equatable {
        let dxmt: Bool
        let d3dmetal: Bool
    }

    let name: String
    let version: String
    let flavor: String
    let wineVersion: String
    let patches: [Patch]
    let files: [String: String]
    let graphics: Graphics
    let bridge: [String: String]

    enum CodingKeys: String, CodingKey {
        case name, version, flavor, patches, files, graphics, bridge
        case wineVersion = "wine_version"
    }
}

struct FerryRunner: Sendable, Equatable {

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case noManifest
        case unreadable(String)
        case unsupportedFlavor(String)
        case missingEntry(String)
        case missingFile(String)
        case hashMismatch(String)
        case invalidVersion(String)
        case unsafePath(String)
        case unreadableFile(String)
        case notFerry

        var description: String {
            switch self {
            case .noManifest: "There is no manifest.json in this folder."
            case .unreadable(let why): "manifest.json could not be read: \(why)"
            case .unsupportedFlavor(let flavor): "This runner is \(flavor); only rosetta is supported."
            case .missingEntry(let path): "manifest.json does not list \(path)."
            case .missingFile(let path): "\(path) is missing from the runner."
            case .hashMismatch(let path): "\(path) does not match manifest.json."
            case .invalidVersion(let version): "\(version) is not a Ferry version (26.3.0-ferry.N)."
            case .unsafePath(let path): "\(path) points outside the runner or through a symlink."
            case .unreadableFile(let path): "\(path) could not be read."
            case .notFerry: "This runner's ntdll is not a Ferry build (no source patches)."
            }
        }
    }

    static let manifestName = "manifest.json"
    static let rootName = "CrossOver"
    static let loaderPath = "lib/wine/x86_64-unix/wine"
    static let unixNtdllPath = "lib/wine/x86_64-unix/ntdll.so"
    // Only a Ferry ntdll.so contains this (patches/wine/0002), so a real CrossOver tree cannot pass
    // for a Ferry runner and skip its licence check by shipping a hand-made manifest.
    // shortcut: a byte marker, not a signature; deliberately editing ntdll.so defeats it. The
    // manifest is unsigned by design (private build, no keys to manage).
    static let ferryMarker = Data("FERRY_DLLPATH_FIRST".utf8)
    // Doubles as a path component (runners/crossover-ferry-<version>) and a compat tool name.
    // Pinned to the one CrossOver source drop Ferry builds from; bump with the source.
    static let versionPattern = #"^26\.3\.0-ferry\.[0-9]+$"#
    static let ntdllPaths: [WineArch: String] = [
        .x86_64Windows: "lib/wine/x86_64-windows/ntdll.dll",
        .i386Windows: "lib/wine/i386-windows/ntdll.dll",
    ]

    let directory: URL
    let manifest: FerryManifest

    var root: URL { directory.appending(path: Self.rootName, directoryHint: .isDirectory) }
    var manifestURL: URL { directory.appending(path: Self.manifestName) }

    // Also names the runner directory: runners/crossover-ferry-<version>
    var buildID: String { "ferry-\(manifest.version)" }

    var expectedNtdll: [WineArch: String] {
        Self.ntdllPaths.compactMapValues { manifest.files[$0] }
    }

    var build: RunnerBuild {
        RunnerBuild(
            bundleVersion: buildID,
            releaseVersion: manifest.version,
            flavor: nil,
            loaderSHA256: manifest.files[Self.loaderPath] ?? "",
            cleanNtdll: [:],
            patchedNtdll: [:],
            // the Steam hook only accepts tools named notproton* (dylib/feats/compat.c)
            tools: [CompatTool(name: "notproton-\(buildID)", flavor: .rosetta, display: "Ferry \(manifest.version) (Rosetta)")],
            ntdllPolicy: .sourcePatched(expected: expectedNtdll)
        )
    }

    // verify: hash every file the manifest lists. Done when a runner is added or installed;
    // the registry's scans of already-installed runners only decode.
    static func load(from directory: URL, verify: Bool = true) throws -> FerryRunner {
        let manifestURL = directory.appending(path: manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw LoadError.noManifest
        }
        let manifest: FerryManifest
        do {
            manifest = try JSONDecoder().decode(FerryManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw LoadError.unreadable(String(describing: error))
        }
        guard manifest.flavor == "rosetta" else { throw LoadError.unsupportedFlavor(manifest.flavor) }
        guard manifest.version.range(of: versionPattern, options: .regularExpression) != nil else {
            throw LoadError.invalidVersion(manifest.version)
        }
        for path in [loaderPath, unixNtdllPath] + ntdllPaths.values.sorted() where manifest.files[path] == nil {
            throw LoadError.missingEntry(path)
        }
        let runner = FerryRunner(directory: directory, manifest: manifest)
        if verify {
            for (path, expected) in manifest.files.sorted(by: { $0.key < $1.key }) {
                let url = try runner.contained(path)
                guard let actual = Digest.sha256IfPresent(url) else { throw LoadError.missingFile(path) }
                guard actual == expected else { throw LoadError.hashMismatch(path) }
            }
            let ntdllURL = try runner.contained(unixNtdllPath)
            guard let ntdll = try? Data(contentsOf: ntdllURL) else { throw LoadError.unreadableFile(unixNtdllPath) }
            guard ntdll.range(of: ferryMarker) != nil else { throw LoadError.notFerry }
        }
        return runner
    }

    // A manifest path as a file inside the runner root: no absolute paths, no "..", and no
    // symlink anywhere from the runner folder down (so nothing outside it is hashed or trusted).
    func contained(_ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw LoadError.unsafePath(path)
        }
        // shortcut: checked, then opened by path (not O_NOFOLLOW), so someone swapping files in
        // the runner folder during verification could race it; out of scope for a personal build.
        var url = directory
        for part in [Self.rootName] + parts.map(String.init) {
            url = url.appending(path: part)
            // lstat, so a dangling symlink is caught too. A missing file is reported later as
            // missingFile; any other lookup failure fails closed.
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            } catch CocoaError.fileReadNoSuchFile {
                return url
            } catch {
                throw LoadError.unsafePath(path)
            }
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw LoadError.unsafePath(path) }
        }
        return url
    }

    static let verifyStep = "Verify Ferry runner"

    // Stands in for NtdllPatcher.stage on a source-patched build: nothing is written, the
    // installed ntdll copies must be the ones the manifest names.
    static func verifyNtdll(_ expected: [WineArch: String], root: URL) throws {
        for (arch, hash) in expected.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let path = ntdllPaths[arch] else { continue }
            guard let actual = Digest.sha256IfPresent(root.appending(path: path)) else {
                throw StepFailure(step: verifyStep, detail: "\(path) is missing from the runner.")
            }
            guard actual == hash else {
                throw StepFailure(step: verifyStep, detail: "\(path) is not the ntdll this Ferry build shipped.")
            }
        }
    }
}

// Ferry builds the app knows about: runners the user added (by folder) and runners already
// installed under the support directory (their manifest is kept beside the clone).
enum FerryRunners {

    private static let manualKey = "ferryRunnerPaths"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: [String: FerryRunner] = [:]

    static func manualDirectories(_ defaults: UserDefaults = .standard) -> [URL] {
        (defaults.stringArray(forKey: manualKey) ?? []).filter { !$0.isEmpty }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    static func addManual(_ directory: URL, _ defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        let current = manualDirectories(defaults)
        guard !current.contains(where: { CrossOverSource.same($0, directory) }) else { return }
        defaults.set((current + [directory]).map { $0.path(percentEncoded: false) }, forKey: manualKey)
    }

    static func removeManual(_ directory: URL, _ defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        let kept = manualDirectories(defaults).filter { !CrossOverSource.same($0, directory) }
        defaults.set(kept.map { $0.path(percentEncoded: false) }, forKey: manualKey)
    }

    static func register(_ runner: FerryRunner) {
        lock.lock()
        defer { lock.unlock() }
        registered[runner.buildID] = runner
    }

    static func unregister(directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        registered = registered.filter { !CrossOverSource.same($0.value.directory, directory) }
    }

    // runners/crossover-ferry-*/manifest.json, decoded only (hashes were checked at install)
    static func installed(runners: URL = SupportPaths.runners) -> [FerryRunner] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: runners, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.lastPathComponent.hasPrefix("crossover-ferry-") }
            .compactMap { try? FerryRunner.load(from: $0, verify: false) }
            .sorted { $0.buildID < $1.buildID }
    }

    static func builds(runners: URL = SupportPaths.runners) -> [RunnerBuild] {
        lock.lock()
        let known = registered
        lock.unlock()
        var byID = known
        for runner in installed(runners: runners) where byID[runner.buildID] == nil { byID[runner.buildID] = runner }
        return byID.values.map(\.build).sorted { $0.id < $1.id }
    }
}

// Ferry: the runner can ship inside Ferry.app (Contents/Resources/ferry-runner.tar.gz, put there
// by runner/make-app.sh), so a fresh install needs nothing but the app. The archive holds one
// folder, ferry-runner-<version>-rosetta/ (CrossOver/ + manifest.json). It is unpacked once per
// version under the support directory, verified against its manifest, and added like a runner
// the user picked; Install then sets it up as usual.
enum BundledFerryRunner {

    static let archiveName = "ferry-runner.tar.gz"

    static var bundledArchive: URL? {
        let url = Bundle.main.resourceURL?.appending(path: archiveName)
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) ? $0 : nil }
    }

    static var unpackRoot: URL { SupportPaths.support.appending(path: "bundled-runner") }

    // The runner folder inside the archive, e.g. ferry-runner-26.3.0-ferry.18-rosetta
    static func folderName(in archive: URL) throws -> String {
        let listing = try Shell.run("/bin/sh", ["-c", "/usr/bin/tar -tzf \"$1\" | head -1", "sh", archive.path(percentEncoded: false)])
        let first = listing.stdout.split(separator: "/").first.map(String.init) ?? ""
        guard first.hasPrefix("ferry-runner-"), !first.contains("..") else {
            throw StepFailure(step: FerryRunner.verifyStep, detail: "The bundled runner archive has an unexpected layout.")
        }
        return first
    }

    // Unpacks (when this version isn't already there), verifies and registers the bundled runner.
    // Returns its folder, or nil when the app carries no runner.
    @discardableResult
    static func ensure(archive: URL? = bundledArchive, root: URL = unpackRoot,
                       defaults: UserDefaults = .standard) throws -> URL? {
        guard let archive else { return nil }
        let name = try folderName(in: archive)
        let target = root.appending(path: name, directoryHint: .isDirectory)
        let fm = FileManager.default

        if !fm.fileExists(atPath: target.appending(path: FerryRunner.manifestName).path(percentEncoded: false)) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let partial = root.appending(path: ".unpacking-\(UUID().uuidString)", directoryHint: .isDirectory)
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: partial) }
            let untar = try Shell.run("/usr/bin/tar", ["-xzf", archive.path(percentEncoded: false), "-C", partial.path(percentEncoded: false)])
            guard untar.succeeded else {
                throw StepFailure(step: FerryRunner.verifyStep, detail: "The bundled runner could not be unpacked. \(untar.stderr)")
            }
            // verify before it can be used: every manifest hash, the Ferry ntdll marker
            _ = try FerryRunner.load(from: partial.appending(path: name, directoryHint: .isDirectory))
            try? fm.removeItem(at: target)
            try fm.moveItem(at: partial.appending(path: name, directoryHint: .isDirectory), to: target)
            // an older bundled version is no longer offered; its set-up clone stays in runners/
            for old in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent != name && old.lastPathComponent.hasPrefix("ferry-runner-") {
                FerryRunners.removeManual(old, defaults)
                FerryRunners.unregister(directory: old)
                try? fm.removeItem(at: old)
            }
            AppLog.note("bundled ferry runner unpacked: \(name)")
        }
        FerryRunners.addManual(target, defaults)
        return target
    }
}
