import AppKit
import MacGameLibrary
import SwiftData
import SwiftUI

@main
struct MacGameLibraryApp: App {
    init() {
        DebugLog.log("App init")
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            DebugLog.log("didFinishLaunching")
        }
        center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            DebugLog.log("willTerminate")
        }
    }

    var sharedModelContainer: ModelContainer = {
        DebugLog.log("Creating ModelContainer at \(PersistenceStoreLocation.storeFileURL.path)")
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
            let container = try ModelContainer(for: schema, configurations: [configuration])
            DebugLog.log("ModelContainer created")
            return container
        } catch {
            DebugLog.log("ModelContainer creation failed: \(error.localizedDescription)")
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

                Button("Missing Orphan Games") {
                    showHelpDialog(
                        title: "Missing Orphan Games",
                        message: """
                        Why this exists:
                        Sometimes old library entries can reference emulator records that no longer exist (for example after emulator edits/imports or stale data). Those entries can show up as ghost games in “All” and not in emulator-specific sections.

                        What the app does:
                        On startup, the app now auto-cleans these orphan entries and shows a cleanup notice if any were removed.

                        Result:
                        Library sections stay consistent, and stale ghost entries no longer cause play/launch instability.
                        """
                    )
                }

                Button("Keystrokes permission") {
                    showHelpDialog(
                        title: "Keystrokes permission",
                        message: """
                        Why macOS prompted this:
                        Some launcher/game components (for example overlays, anti-cheat, controller/input hooks, or launcher helpers) request Input Monitoring or Accessibility permissions to watch low-level input events.

                        Important:
                        This prompt is separate from account login. Being signed in to Epic does not always prevent it.

                        What you can do:
                        You can click Deny first and try launching the game anyway. Many games still run without this permission.

                        If the game fails after Deny:
                        That specific title/runtime likely requires elevated input access on macOS.
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
