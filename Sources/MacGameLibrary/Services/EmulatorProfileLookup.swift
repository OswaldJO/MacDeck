import Foundation
import SwiftData

/// Resolves [EmulatorProfile] for a library game when the SwiftData relationship is stale.
enum EmulatorProfileLookup {
    static func resolve(for game: LibraryGame, context: ModelContext, persistRepair: Bool = true) -> EmulatorProfile? {
        if let linked = game.emulator {
            return linked
        }
        if let uuid = game.emulatorUUID {
            var descriptor = FetchDescriptor<EmulatorProfile>(predicate: #Predicate { $0.id == uuid })
            descriptor.fetchLimit = 1
            if let profile = try? context.fetch(descriptor).first {
                game.emulator = profile
                return profile
            }
        }
        guard let inferred = RomPathPlatformResolver.emulator(forRomPath: game.romPath, context: context) else {
            return nil
        }
        if persistRepair {
            game.emulator = inferred
            game.emulatorIDString = inferred.id.uuidString
            if game.platformHint == nil {
                game.platformHint = EmulatorPlatformResolver.resolve(emulator: inferred)?.primaryPlatformHint
            }
            try? context.save()
        }
        return inferred
    }
}
