import Foundation

/// Resolves a Sunshine executable: bundled copy first, then common install locations.
enum SunshineBinaryLocator {
    enum LocatorError: Error, LocalizedError {
        case notFound

        var errorDescription: String? {
            """
            Sunshine was not found. Run: ./Scripts/stage-sunshine-for-mac-app.sh --install
            Or: brew tap LizardByte/homebrew && brew install lizardbyte/homebrew/sunshine
            """
        }
    }

    /// Human-readable label for the resolved binary (for status UI).
    static func resolvedLabel() -> String? {
        guard let url = try? locate() else { return nil }
        if let resource = Bundle.main.resourceURL,
           url.path.hasPrefix(resource.path) {
            return "Bundled in app"
        }
        return url.path
    }

    static func locate() throws -> URL {
        if let bundled = bundledBinary(), FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        var candidates = [
            "/opt/homebrew/bin/sunshine",
            "/usr/local/bin/sunshine",
            "/opt/homebrew/opt/sunshine/bin/sunshine",
            "/usr/local/opt/sunshine/bin/sunshine",
            "/Applications/Sunshine.app/Contents/MacOS/sunshine",
        ]
        if let brewPrefix = brewPrefixSunshine() {
            candidates.insert(brewPrefix.path + "/bin/sunshine", at: 0)
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let which = whichSunshine() {
            return which
        }

        throw LocatorError.notFound
    }

    private static func bundledBinary() -> URL? {
        if let url = Bundle.main.url(forResource: "sunshine", withExtension: nil, subdirectory: "Sunshine") {
            return url
        }
        return Bundle.main.resourceURL?
            .appending(path: "Sunshine/sunshine")
    }

    private static func brewPrefixSunshine() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        if !FileManager.default.isExecutableFile(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
        }
        guard FileManager.default.isExecutableFile(atPath: process.executableURL!.path) else {
            return nil
        }
        process.arguments = ["--prefix", "sunshine"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let prefix = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !prefix.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: prefix)
    }

    private static func whichSunshine() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["sunshine"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
