import MacGameLibrary
import SwiftData
import SwiftUI

@main
struct MacGameLibraryApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            EmulatorProfile.self,
            LibraryGame.self,
            GameFolderPath.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            url: PersistenceStoreLocation.storeFileURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
