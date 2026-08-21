import Foundation

enum InstallOutcome {
    case success
    case failure
}

/// Accumulates raw process output into lines. `readabilityHandler` and
/// `terminationHandler` can each fire on their own queue, so all access to
/// the buffer is serialized through a lock rather than captured as a bare var.
private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var carry = Data()

    /// Appends a chunk and returns any complete (newline-terminated) lines.
    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        carry.append(data)
        var lines: [String] = []
        while let newlineRange = carry.range(of: Data([0x0A])) {
            let lineData = carry.subdata(in: carry.startIndex..<newlineRange.lowerBound)
            carry.removeSubrange(carry.startIndex..<newlineRange.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }

    /// Returns whatever partial line is left once the process has exited.
    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        defer { carry.removeAll() }
        return String(data: carry, encoding: .utf8)
    }
}

enum Installer {
    /// Runs an app's reinstall script to completion. The script itself is
    /// responsible for resetting the expiry clock on success. Pass/fail is
    /// reported back via the return value; `onOutput` is called on the main
    /// thread with each line the script prints (stdout and stderr merged,
    /// interleaved in real time) so the UI can surface progress as it happens.
    static func run(
        scriptPath: String,
        args: [String] = [],
        onOutput: @escaping (String) -> Void = { _ in }
    ) async -> InstallOutcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            // `-l` (login shell) matters: these scripts shell out to tools
            // like `pod` and `xcodegen` that live in /opt/homebrew/bin, which
            // is only on PATH once /etc/profile's path_helper has run. A
            // GUI app's inherited PATH is the bare macOS default and won't
            // find them otherwise. Passing the script as an argument (rather
            // than via -c string interpolation) keeps args array-safe.
            process.arguments = ["-l", scriptPath] + args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let accumulator = LineAccumulator()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in accumulator.append(data)
                where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    DispatchQueue.main.async { onOutput(line) }
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                // Flush any trailing partial line left in the buffer.
                if let line = accumulator.flush(),
                   !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    DispatchQueue.main.async { onOutput(line) }
                }
                continuation.resume(returning: proc.terminationStatus == 0 ? .success : .failure)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure)
            }
        }
    }
}
