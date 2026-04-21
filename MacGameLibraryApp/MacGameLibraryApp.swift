import AppKit
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
        .commands {
            CommandGroup(replacing: .help) {
                Button("RetroArch Launch Arguments") {
                    showHelpDialog(
                        title: "RetroArch Launch Arguments",
                        message: """
                        RetroArch cores on Mac are typically stored in:
                        ~/Library/Application Support/RetroArch/cores

                        To access this folder:
                        Open Finder, click Go in the menu bar, select Go to Folder, and paste:
                        ~/Library/Application Support/RetroArch/

                        Paths can differ between standard and Steam installs.

                        Example launch arguments:
                        -L "/Users/{user_name}/Library/Application Support/RetroArch/cores/mgba_libretro.dylib" --fullscreen "{ImagePath}"
                        """
                    )
                }

                Button("RPCS3 Game not launching") {
                    showHelpDialog(
                        title: "RPCS3 Game not launching",
                        message: """
                        Edge case:
                        If RPCS3 is already open, launching a different PS3 game from this library may not switch games reliably.

                        Workaround:
                        Close RPCS3 first, then launch the other PS3 game from the library.
                        """
                    )
                }
            }
        }
    }

    private func showHelpDialog(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
