import SwiftUI

/// ScreenScraper API credentials used by metadata background fetches.
struct ScreenScraperSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var devID: String = MetadataCredentials.screenScraperDevID ?? ""
    @State private var devPassword: String = MetadataCredentials.screenScraperDevPassword ?? ""
    @State private var userID: String = MetadataCredentials.screenScraperUserID ?? ""
    @State private var userPassword: String = MetadataCredentials.screenScraperUserPassword ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Enter ScreenScraper API credentials. `devid` and `devpassword` are required. `ssid` and `sspassword` are optional user credentials."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Link("ScreenScraper Web API v2", destination: URL(string: "https://www.screenscraper.fr/webapi2.php")!)
                }

                Section("Credentials") {
                    TextField("Developer ID (devid)", text: $devID)
                        .textContentType(.username)
                    SecureField("Developer Password (devpassword)", text: $devPassword)
                        .textContentType(.password)
                    TextField("User ID (ssid, optional)", text: $userID)
                        .textContentType(.username)
                    SecureField("User Password (sspassword, optional)", text: $userPassword)
                        .textContentType(.password)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Metadata (ScreenScraper)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MetadataCredentials.screenScraperDevID = devID.trimmingCharacters(in: .whitespacesAndNewlines)
                        MetadataCredentials.screenScraperDevPassword = devPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                        MetadataCredentials.screenScraperUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
                        MetadataCredentials.screenScraperUserPassword = userPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}

#Preview {
    ScreenScraperSettingsSheet()
}
