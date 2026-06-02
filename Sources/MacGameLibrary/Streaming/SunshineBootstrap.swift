import Foundation

/// Writes Playnite-managed Sunshine config and applies web UI credentials via `sunshine --creds`.
enum SunshineBootstrap {
    enum BootstrapError: Error, LocalizedError {
        case commandFailed(String, Int32)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let detail, let code):
                return "Sunshine setup failed (exit \(code)): \(detail)"
            }
        }
    }

    static func prepareEnvironment() throws {
        try SunshinePaths.ensureConfigDirectory()
        try writeConfigIfNeeded()
        StreamingHostSettings.ensureGeneratedCredentials()
    }

    static func syncCredentialsToSunshine() async throws {
        try prepareEnvironment()
        let binary = try SunshineBinaryLocator.locate()
        let (username, password) = (
            StreamingHostSettings.username,
            StreamingHostSettings.password
        )
        guard !username.isEmpty, !password.isEmpty else {
            throw StreamingControlPlaneError.missingCredentials
        }

        let needsApply = !FileManager.default.fileExists(atPath: SunshinePaths.credentialsFile.path)
            || StreamingHostSettings.credentialsNeedSunshineSync

        guard needsApply else { return }

        try await runSunshineCommand(
            binary: binary,
            arguments: [
                SunshinePaths.configFile.path,
                "--creds",
                username,
                password,
            ]
        )
        try importCredentialsIfNeeded()
        StreamingHostSettings.markCredentialsSyncedToSunshine()
    }

    private static func writeConfigIfNeeded() throws {
        let path = SunshinePaths.configFile
        let credentialsPath = SunshinePaths.credentialsFile.path
        let body = """
        # Managed by Playnite Mac — do not edit unless you know what you are doing.
        credentials_file = \(credentialsPath)
        port = \(ControlPlanePorts.moonlightHTTP)
        origin_web_ui_allowed = lan
        """
        if FileManager.default.fileExists(atPath: path.path),
           let existing = try? String(contentsOf: path, encoding: .utf8),
           existing.contains(credentialsPath) {
            return
        }
        try body.write(to: path, atomically: true, encoding: .utf8)
    }

    /// `sunshine --creds` writes to `~/.config/sunshine/`; copy into our isolated config dir.
    private static func importCredentialsIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: SunshinePaths.credentialsFile.path) else {
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultState = home
            .appending(path: ".config/sunshine/\(SunshinePaths.credentialsFileName)")
        guard FileManager.default.fileExists(atPath: defaultState.path) else { return }
        try FileManager.default.copyItem(at: defaultState, to: SunshinePaths.credentialsFile)
    }

    private static func runSunshineCommand(binary: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.currentDirectoryURL = SunshinePaths.configDirectory

            let stderr = Pipe()
            process.standardOutput = Pipe()
            process.standardError = stderr

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    let detail = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                    continuation.resume(throwing: BootstrapError.commandFailed(detail, proc.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
