import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String

    public init(exitCode: Int32, stdout: Data, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// What happens to a running command when the task waiting for it is cancelled.
public enum StopStyle: Equatable, Sendable {
    /// SIGTERM, SIGKILL shortly after, and `CancellationError` at once: nobody wants the answer.
    case terminate
    /// SIGINT, as Ctrl-C sends it, then wait: the command's own result is returned once it has
    /// exited. bd answers the signal by finishing what it is writing, cancelling the rest and
    /// exiting (plan 0007). A second SIGINT follows if it is still running after a while, on
    /// which bd exits at once, and SIGKILL only after that.
    case interrupt
}

public protocol CommandRunning: Sendable {
    /// `directory` is the working directory for the process; nil inherits the app's.
    func run(_ executable: URL, arguments: [String], directory: URL?, timeout: TimeInterval) async throws -> CommandResult
    func run(_ executable: URL, arguments: [String], directory: URL?, timeout: TimeInterval, stop: StopStyle) async throws -> CommandResult
}

extension CommandRunning {
    public func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await run(executable, arguments: arguments, directory: nil, timeout: timeout)
    }

    /// A runner that doesn't know about stop styles stops everything the one way it knows.
    public func run(_ executable: URL, arguments: [String], directory: URL?, timeout: TimeInterval, stop: StopStyle) async throws -> CommandResult {
        try await run(executable, arguments: arguments, directory: directory, timeout: timeout)
    }
}

public struct ProcessCommandRunner: CommandRunning {
    private let environment: [String: String]
    /// After the first SIGINT of an interrupt, how long before the second.
    private let interruptGrace: TimeInterval
    /// After the second SIGINT, how long before SIGKILL.
    private let killGrace: TimeInterval

    public init(
        environment: [String: String] = ProcessCommandRunner.defaultEnvironment(),
        interruptGrace: TimeInterval = 10,
        killGrace: TimeInterval = 5
    ) {
        self.environment = environment
        self.interruptGrace = interruptGrace
        self.killGrace = killGrace
    }

    /// The inherited environment with Homebrew locations appended to PATH, since apps
    /// launched from Finder don't get the login shell's PATH.
    public static func defaultEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        let existing = (base["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        let extra = ["/opt/homebrew/bin", "/usr/local/bin"].filter { !existing.contains($0) }
        environment["PATH"] = (existing + extra).joined(separator: ":")
        return environment
    }

    /// Throws `BeadsDataError.timedOut` after `timeout`, or `CancellationError` if the task is
    /// cancelled; either way the process is stopped rather than left running.
    public func run(_ executable: URL, arguments: [String], directory: URL?, timeout: TimeInterval) async throws -> CommandResult {
        try await run(executable, arguments: arguments, directory: directory, timeout: timeout, stop: .terminate)
    }

    /// With `.interrupt`, cancellation doesn't throw: the process is asked to stop and what it
    /// then reports is returned, exit code and all.
    public func run(_ executable: URL, arguments: [String], directory: URL?, timeout: TimeInterval, stop: StopStyle) async throws -> CommandResult {
        let run = ProcessRun(executable: executable, arguments: arguments, directory: directory, environment: environment)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            switch stop {
            case .terminate: run.cancel()
            case .interrupt: run.interrupt(secondAfter: interruptGrace, killAfter: killGrace)
            }
        }
    }
}

/// One child process. Both pipes are drained as data arrives so a chatty child can never
/// block on a full pipe. The result is delivered exactly once: when the process has exited
/// and its pipes have closed (or shortly after exit, if a grandchild keeps them open), or
/// when the timeout fires, or on cancellation.
private final class ProcessRun: @unchecked Sendable {
    /// After exit, how long to wait for pipes that an inherited descendant may hold open.
    private static let pipeGrace: TimeInterval = 0.5
    /// After SIGTERM, how long before SIGKILL. bd traps SIGTERM to flush pending work.
    private static let killGrace: TimeInterval = 2

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var openPipes = 2
    private var launched = false
    private var exited = false
    private var cancelled = false
    private var interruptRequested = false
    private var timedOut = false
    private var timeoutSeconds = 0
    private var continuation: CheckedContinuation<CommandResult, Error>?
    private var timeoutWork: DispatchWorkItem?

    init(executable: URL, arguments: [String], directory: URL?, environment: [String: String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
    }

    func start(timeout: TimeInterval, continuation: CheckedContinuation<CommandResult, Error>) {
        let alreadyCancelled = lock.withLock {
            self.continuation = continuation
            return cancelled
        }
        guard !alreadyCancelled else { return finish(.failure(CancellationError())) }

        for (pipe, isStdout) in [(stdoutPipe, true), (stderrPipe, false)] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self, !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    self?.pipeClosed()
                    return
                }
                self.lock.withLock {
                    if isStdout { self.stdout.append(chunk) } else { self.stderr.append(chunk) }
                }
            }
        }
        process.terminationHandler = { [weak self] _ in self?.processExited() }

        do {
            try process.run()
        } catch {
            return finish(.failure(error))
        }

        let work = DispatchWorkItem { [weak self] in self?.timeoutFired(seconds: Int(timeout.rounded())) }
        let cancelledWhileLaunching = lock.withLock {
            launched = true
            timeoutWork = work
            return cancelled
        }
        let interruptedWhileLaunching = lock.withLock { interruptRequested }
        if cancelledWhileLaunching {
            stop()
        } else if interruptedWhileLaunching {
            sendInterrupts()
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
        }
    }

    func cancel() {
        let wasLaunched = lock.withLock {
            cancelled = true
            return launched
        }
        if wasLaunched { stop() }
        finish(.failure(CancellationError()))
    }

    /// Asks the process to stop and leaves the result to its exit: nothing is reported here.
    /// A process that was never launched has no answer to wait for, so that is a cancellation.
    func interrupt(secondAfter: TimeInterval, killAfter: TimeInterval) {
        let (wasLaunched, hasContinuation) = lock.withLock {
            interruptRequested = true
            interruptGraces = (secondAfter, killAfter)
            return (launched, continuation != nil)
        }
        if wasLaunched {
            sendInterrupts()
        } else if !hasContinuation {
            // Cancelled before `start`: let `start` see it as a cancellation.
            lock.withLock { cancelled = true }
        }
    }

    private var interruptGraces: (second: TimeInterval, kill: TimeInterval) = (10, 5)

    /// SIGINT; a second if the process is still there after a while; then SIGKILL.
    private func sendInterrupts() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let graces = lock.withLock { interruptGraces }
        process.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + graces.second) { [self] in
            guard !lock.withLock({ exited }) else { return }
            kill(pid, SIGINT)
            DispatchQueue.global().asyncAfter(deadline: .now() + graces.kill) { [self] in
                if !lock.withLock({ exited }) { kill(pid, SIGKILL) }
            }
        }
    }

    private func pipeClosed() {
        let done = lock.withLock {
            openPipes -= 1
            return openPipes == 0 && exited
        }
        if done { complete() }
    }

    private func processExited() {
        let (pipesClosed, didTimeOut) = lock.withLock {
            exited = true
            return (openPipes == 0, timedOut)
        }
        if pipesClosed || didTimeOut {
            complete()
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.pipeGrace) { [weak self] in
                self?.complete()
            }
        }
    }

    /// The one place a finished process is reported, so a timeout can never be overtaken by the
    /// pipes closing a moment after exit and reported as success — and nor can a cancellation:
    /// the SIGTERM it sends makes the process exit, and that exit must not read as a result.
    private func complete() {
        let outcome: Result<CommandResult, Error> = lock.withLock {
            if cancelled {
                return .failure(CancellationError())
            }
            if timedOut {
                return .failure(BeadsDataError.timedOut(seconds: timeoutSeconds))
            }
            return .success(CommandResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: String(decoding: stderr, as: UTF8.self)
            ))
        }
        finish(outcome)
    }

    /// Stops the process, but reports the timeout only once it has exited (or the kill backstop
    /// passes). bd flushes pending commits on SIGTERM, and callers re-read right after a timeout,
    /// so they must not look before bd is done.
    private func timeoutFired(seconds: Int) {
        let shouldStop = lock.withLock {
            guard continuation != nil, !exited else { return false }
            timedOut = true
            timeoutSeconds = seconds
            return true
        }
        guard shouldStop else { return }
        stop()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGrace + 1) { [self] in
            finish(.failure(BeadsDataError.timedOut(seconds: seconds)))
        }
    }

    /// SIGTERM now, SIGKILL shortly after if the process still hasn't exited.
    private func stop() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGrace) { [self] in
            if !lock.withLock({ exited }) {
                kill(pid, SIGKILL)
            }
        }
    }

    private func finish(_ result: Result<CommandResult, Error>) {
        let (pending, work) = lock.withLock {
            defer {
                continuation = nil
                timeoutWork = nil
            }
            return (continuation, timeoutWork)
        }
        guard let pending else { return }
        work?.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        pending.resume(with: result)
    }
}
