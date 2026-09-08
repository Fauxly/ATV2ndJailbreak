import Foundation

/// Wraps Process to run shell commands with streaming output.
class ProcessRunner {

    func run(
        command: String,
        currentDirectory: String? = nil,
        environment: [String: String]? = nil,
        onOutput: @escaping @Sendable (String) -> Void,
        onComplete: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        // Merge custom env with inherited
        var env = ProcessInfo.processInfo.environment
        if let extra = environment {
            for (k, v) in extra { env[k] = v }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var allOutput = ""
        let lock = NSLock()

        // Stream stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            allOutput += str
            lock.unlock()
            for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                onOutput(line)
            }
        }

        // Stream stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            allOutput += str
            lock.unlock()
            for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                onOutput("[stderr] \(line)")
            }
        }

        process.terminationHandler = { proc in
            // Clean up handlers
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            // Read remaining data
            if let remaining = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                lock.lock()
                allOutput += remaining
                lock.unlock()
            }

            lock.lock()
            let finalOutput = allOutput
            lock.unlock()

            if proc.terminationStatus == 0 {
                onComplete(.success(finalOutput))
            } else {
                let error = ProcessError.exitCode(
                    Int(proc.terminationStatus),
                    output: finalOutput
                )
                onComplete(.failure(error))
            }
        }

        do {
            try process.run()
        } catch {
            onComplete(.failure(error))
        }
    }
}

// MARK: - Error

enum ProcessError: LocalizedError {
    case exitCode(Int, output: String)

    var errorDescription: String? {
        switch self {
        case .exitCode(let code, let output):
            let snippet = output.suffix(200)
            return "Process exited with code \(code): …\(snippet)"
        }
    }
}
