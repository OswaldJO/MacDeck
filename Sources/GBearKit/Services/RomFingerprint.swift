import CryptoKit
import Foundation
import zlib

/// File attributes sent to ScreenScraper `jeuInfos.php` for checksum / exact-filename matching.
struct RomFingerprint: Sendable {
    let romFileName: String
    let fileSize: Int64
    let romType: String
    let md5Hash: String?
    let crc32Hash: String?
    let sha1Hash: String?
    /// Extra `romnom` values to try for exact-filename lookup (e.g. hashed `.bin` inside a `.cue`).
    let alternateRomFileNames: [String]

    /// Largest hashable file for a library launch path (cue/m3u resolved to payload file when possible).
    static func build(forRomPath romPath: String) async -> RomFingerprint? {
        await Task.detached(priority: .utility) {
            buildSync(forRomPath: romPath)
        }.value
    }

    private static func buildSync(forRomPath romPath: String) -> RomFingerprint? {
        let standardized = (romPath as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: standardized)
        if isDirectory.boolValue {
            return folderFingerprint(rootURL: rootURL)
        }

        let ext = rootURL.pathExtension.lowercased()
        switch ext {
        case "cue":
            if let binURL = cuePayloadURL(cueURL: rootURL) {
                return fileFingerprint(
                    fileURL: binURL,
                    romFileName: rootURL.lastPathComponent,
                    alternateRomFileNames: alternates(for: rootURL.lastPathComponent, payloadURL: binURL)
                )
            }
            return fileFingerprint(fileURL: rootURL, romFileName: rootURL.lastPathComponent)
        case "m3u", "m3u8":
            if let payload = m3uPayloadURL(m3uURL: rootURL) {
                return fileFingerprint(
                    fileURL: payload,
                    romFileName: rootURL.lastPathComponent,
                    alternateRomFileNames: alternates(for: rootURL.lastPathComponent, payloadURL: payload)
                )
            }
            return fileFingerprint(fileURL: rootURL, romFileName: rootURL.lastPathComponent)
        default:
            if let dossierRoot = installedTitleFolderRoot(for: rootURL) {
                return folderFingerprint(rootURL: dossierRoot)
            }
            return fileFingerprint(fileURL: rootURL, romFileName: rootURL.lastPathComponent)
        }
    }

    func withoutChecksums() -> RomFingerprint {
        RomFingerprint(
            romFileName: romFileName,
            fileSize: fileSize,
            romType: romType,
            md5Hash: nil,
            crc32Hash: nil,
            sha1Hash: nil,
            alternateRomFileNames: alternateRomFileNames
        )
    }

    func withRomFileName(_ name: String) -> RomFingerprint {
        RomFingerprint(
            romFileName: name,
            fileSize: fileSize,
            romType: romType,
            md5Hash: md5Hash,
            crc32Hash: crc32Hash,
            sha1Hash: sha1Hash,
            alternateRomFileNames: alternateRomFileNames
        )
    }

    private var uniqueRomFileNames: [String] {
        var names: [String] = []
        for candidate in [romFileName] + alternateRomFileNames {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !names.contains(trimmed) else { continue }
            names.append(trimmed)
        }
        return names
    }

    var hashLookupCandidates: [RomFingerprint] {
        uniqueRomFileNames.map { withRomFileName($0) }
    }

    var exactFilenameCandidates: [RomFingerprint] {
        uniqueRomFileNames.map { withRomFileName($0).withoutChecksums() }
    }

    // MARK: - File / folder

    private static func fileFingerprint(
        fileURL: URL,
        romFileName: String,
        alternateRomFileNames: [String] = []
    ) -> RomFingerprint? {
        guard let size = fileByteSize(fileURL) else { return nil }
        let romType = screenScraperRomType(for: fileURL)
        let hashes = computeHashes(fileURL: fileURL)
        return RomFingerprint(
            romFileName: romFileName,
            fileSize: size,
            romType: romType,
            md5Hash: hashes?.md5,
            crc32Hash: hashes?.crc32,
            sha1Hash: hashes?.sha1,
            alternateRomFileNames: alternateRomFileNames
        )
    }

    private static func alternates(for launchName: String, payloadURL: URL) -> [String] {
        let payloadName = payloadURL.lastPathComponent
        return payloadName == launchName ? [] : [payloadName]
    }

    private static func folderFingerprint(rootURL: URL) -> RomFingerprint? {
        let size = directoryByteSize(rootURL) ?? 0
        return RomFingerprint(
            romFileName: rootURL.lastPathComponent,
            fileSize: size,
            romType: "dossier",
            md5Hash: nil,
            crc32Hash: nil,
            sha1Hash: nil,
            alternateRomFileNames: []
        )
    }

    private static func installedTitleFolderRoot(for fileURL: URL) -> URL? {
        var current = fileURL.deletingLastPathComponent()
        for _ in 0 ..< 6 {
            let sfo = current.appendingPathComponent("PARAM.SFO")
            let ps3Game = current.appendingPathComponent("PS3_GAME/PARAM.SFO")
            if FileManager.default.fileExists(atPath: sfo.path)
                || FileManager.default.fileExists(atPath: ps3Game.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    // MARK: - Cue / m3u

    private static func cuePayloadURL(cueURL: URL) -> URL? {
        guard let text = try? String(contentsOf: cueURL, encoding: .utf8) else { return nil }
        let folder = cueURL.deletingLastPathComponent()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("FILE ") else { continue }
            guard let open = trimmed.firstIndex(of: "\""),
                  let close = trimmed[open...].dropFirst().firstIndex(of: "\"") else { continue }
            let name = String(trimmed[trimmed.index(after: open) ..< close])
            let candidate = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func m3uPayloadURL(m3uURL: URL) -> URL? {
        guard let text = try? String(contentsOf: m3uURL, encoding: .utf8) else { return nil }
        let folder = m3uURL.deletingLastPathComponent()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let candidate = trimmed.hasPrefix("/")
                ? URL(fileURLWithPath: trimmed)
                : folder.appendingPathComponent(trimmed)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Hashes

    private struct FileHashes {
        let md5: String
        let crc32: String
        let sha1: String
    }

    private static let hashChunkSize = 1_048_576

    private static func computeHashes(fileURL: URL) -> FileHashes? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var crc: uLong = crc32(0, nil, 0)

        while true {
            guard let chunk = try? handle.read(upToCount: hashChunkSize), !chunk.isEmpty else { break }
            md5.update(data: chunk)
            sha1.update(data: chunk)
            chunk.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
                crc = crc32(crc, base, uInt(chunk.count))
            }
        }

        let md5Hex = md5.finalize().map { String(format: "%02x", $0) }.joined()
        let sha1Hex = sha1.finalize().map { String(format: "%02x", $0) }.joined()
        let crcHex = String(format: "%08x", UInt32(truncatingIfNeeded: crc))
        return FileHashes(md5: md5Hex, crc32: crcHex, sha1: sha1Hex)
    }

    private static func screenScraperRomType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "iso", "cue", "chd", "gdi", "cdi", "bin", "mdf", "img":
            return "iso"
        default:
            return "rom"
        }
    }

    private static func fileByteSize(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private static func directoryByteSize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
