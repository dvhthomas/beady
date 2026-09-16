import BeadsData
import Foundation
import Testing

@Suite("bd executable locator")
struct BDExecutableLocatorTests {
    let home = URL(fileURLWithPath: "/Users/me")

    @Test("BD_PATH wins when it points at an executable")
    func override() throws {
        let locator = BDExecutableLocator(
            environment: ["BD_PATH": "/custom/bd", "PATH": "/usr/bin"],
            homeDirectory: home,
            isExecutable: { $0 == "/custom/bd" || $0 == "/opt/homebrew/bin/bd" }
        )
        #expect(try locator.locate().path == "/custom/bd")
    }

    @Test("searches PATH before well-known install locations, without duplicates")
    func searchOrder() {
        let locator = BDExecutableLocator(
            environment: ["PATH": "/usr/bin:/opt/homebrew/bin"],
            homeDirectory: home,
            isExecutable: { _ in false }
        )
        #expect(locator.candidates() == [
            "/usr/bin/bd", "/opt/homebrew/bin/bd", "/usr/local/bin/bd",
            "/Users/me/go/bin/bd", "/Users/me/.local/bin/bd",
        ])
    }

    @Test("GUI apps get a minimal PATH, so well-known locations still find bd")
    func guiPath() throws {
        let locator = BDExecutableLocator(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: home,
            isExecutable: { $0 == "/opt/homebrew/bin/bd" }
        )
        #expect(try locator.locate().path == "/opt/homebrew/bin/bd")
    }

    @Test("reports every place it looked")
    func notFound() {
        let locator = BDExecutableLocator(environment: [:], homeDirectory: home, isExecutable: { _ in false })
        #expect(throws: BeadsDataError.bdNotFound(searched: locator.candidates())) { try locator.locate() }
    }
}

@Suite("beads workspace")
struct BeadsWorkspaceTests {
    /// A `.beads` folder that bd has initialised.
    func makeBeads(in dir: URL) throws -> URL {
        let beads = dir.appendingPathComponent(".beads")
        try FileManager.default.createDirectory(at: beads, withIntermediateDirectories: true)
        try Data(#"{"backend": "dolt"}"#.utf8).write(to: beads.appendingPathComponent("metadata.json"))
        return beads
    }

    @Test("a project folder containing an initialised .beads is a workspace")
    func projectFolder() throws {
        let dir = try makeTempDirectory()
        _ = try makeBeads(in: dir)
        let workspace = try BeadsWorkspace.resolve(dir)
        #expect(workspace.projectDirectory.standardizedFileURL == dir.standardizedFileURL)
        #expect(workspace.displayName == dir.lastPathComponent)
    }

    @Test("choosing the .beads folder itself resolves to its project")
    func beadsFolder() throws {
        let dir = try makeTempDirectory()
        let beads = try makeBeads(in: dir)
        #expect(try BeadsWorkspace.resolve(beads).projectDirectory.standardizedFileURL == dir.standardizedFileURL)
    }

    @Test("an empty .beads folder is rejected; bd would silently use a parent folder's database")
    func emptyBeadsFolder() throws {
        let dir = try makeTempDirectory()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".beads"), withIntermediateDirectories: true)
        #expect(throws: BeadsDataError.notAWorkspace(path: dir.path)) { try BeadsWorkspace.resolve(dir) }
    }

    @Test("a folder without .beads is rejected")
    func notAWorkspace() throws {
        let dir = try makeTempDirectory()
        #expect(throws: BeadsDataError.notAWorkspace(path: dir.path)) { try BeadsWorkspace.resolve(dir) }
    }
}

@Suite("workspace change probe")
struct WorkspaceChangeProbeTests {
    @Test("fingerprint is stable until bd touches the database")
    func detectsWrites() throws {
        let dir = try makeTempDirectory()
        let beads = dir.appendingPathComponent(".beads")
        try FileManager.default.createDirectory(at: beads, withIntermediateDirectories: true)
        let touched = beads.appendingPathComponent("last-touched")
        try "a".write(to: touched, atomically: true, encoding: .utf8)

        let probe = BDGateway(
            workspace: BeadsWorkspace(projectDirectory: dir),
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            runner: FakeRunner { _ in ok("") }
        )
        let first = probe.changeToken()
        #expect(probe.changeToken() == first)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: touched.path)
        #expect(probe.changeToken() != first)
    }

    @Test("Dolt storage counts by size only: reads bump mtimes, writes grow the journal")
    func doltSizesOnly() throws {
        let dir = try makeTempDirectory()
        let noms = dir.appendingPathComponent(".beads/embeddeddolt/db/.dolt/noms")
        try FileManager.default.createDirectory(at: noms, withIntermediateDirectories: true)
        let journal = noms.appendingPathComponent("vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv")
        let index = noms.appendingPathComponent("journal.idx")
        try Data("abc".utf8).write(to: journal)
        try Data("i".utf8).write(to: index)

        let probe = BDGateway(
            workspace: BeadsWorkspace(projectDirectory: dir),
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            runner: FakeRunner { _ in ok("") }
        )
        let first = probe.changeToken()

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: journal.path)
        #expect(probe.changeToken() == first, "a read that only touches mtimes is not a change")

        try Data("index rewritten".utf8).write(to: index)
        #expect(probe.changeToken() == first, "journal.idx is a derived index; ignore it")

        try Data("abcdef".utf8).write(to: journal)
        #expect(probe.changeToken() != first)
    }
}

@Suite("process command runner")
struct ProcessCommandRunnerTests {
    let sh = URL(fileURLWithPath: "/bin/sh")

    @Test("captures stdout, stderr and exit code")
    func captures() async throws {
        let result = try await ProcessCommandRunner().run(sh, arguments: ["-c", "echo out; echo err >&2; exit 3"], timeout: 10)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "out\n")
        #expect(result.stderr == "err\n")
        #expect(result.exitCode == 3)
    }

    @Test("large output doesn't deadlock the pipe")
    func largeOutput() async throws {
        let result = try await ProcessCommandRunner().run(sh, arguments: ["-c", "head -c 2000000 /dev/zero"], timeout: 20)
        #expect(result.stdout.count == 2_000_000)
    }

    @Test("a hung command is terminated after the timeout")
    func timeout() async throws {
        await #expect(throws: BeadsDataError.timedOut(seconds: 1)) {
            try await ProcessCommandRunner().run(sh, arguments: ["-c", "sleep 30"], timeout: 1)
        }
    }

    @Test("a timeout is only reported once the process has exited, so work it flushes on SIGTERM is visible")
    func timeoutWaitsForExit() async throws {
        let marker = try makeTempDirectory().appendingPathComponent("flushed")
        let script = "trap 'sleep 0.4; touch \"\(marker.path)\"; exit 0' TERM; while true; do sleep 0.1; done"
        await #expect(throws: BeadsDataError.timedOut(seconds: 1)) {
            try await ProcessCommandRunner().run(sh, arguments: ["-c", script], timeout: 1)
        }
        #expect(FileManager.default.fileExists(atPath: marker.path), "the timeout returned before the flush finished")
    }

    @Test("a child that ignores SIGTERM is killed after the timeout, so bd runs can't pile up")
    func killsStubbornChild() async throws {
        let pidFile = try makeTempDirectory().appendingPathComponent("pid")
        let script = "trap '' TERM; echo $$ > '\(pidFile.path)'; exec sleep 30"
        await #expect(throws: BeadsDataError.timedOut(seconds: 1)) {
            try await ProcessCommandRunner().run(sh, arguments: ["-c", script], timeout: 1)
        }
        let pid = try #require(readPID(pidFile))
        #expect(await waitUntil(seconds: 6) { kill(pid, 0) != 0 }, "process \(pid) survived the timeout")
    }

    @Test("returns once the process exits, even if a grandchild still holds the pipe")
    func grandchildHoldsPipe() async throws {
        let started = Date()
        let result = try await ProcessCommandRunner().run(sh, arguments: ["-c", "(sleep 5 &); echo done"], timeout: 10)
        #expect(result.exitCode == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "done\n")
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test("cancelling the task stops the process")
    func cancellation() async throws {
        let pidFile = try makeTempDirectory().appendingPathComponent("pid")
        let script = "echo $$ > '\(pidFile.path)'; exec sleep 30"
        let task = Task { try await ProcessCommandRunner().run(sh, arguments: ["-c", script], timeout: 60) }
        #expect(await waitUntil(seconds: 5) { readPID(pidFile) != nil })
        let pid = try #require(readPID(pidFile))

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await waitUntil(seconds: 6) { kill(pid, 0) != 0 }, "process \(pid) survived cancellation")
    }
}
