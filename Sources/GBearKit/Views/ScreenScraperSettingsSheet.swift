import SwiftUI

/// End-user ScreenScraper account credentials (developer API keys are embedded in the app).
struct ScreenScraperSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var userID: String = MetadataCredentials.screenScraperUserID ?? ""
    @State private var userPassword: String = MetadataCredentials.screenScraperUserPassword ?? ""
    @State private var preferredRegion: String = MetadataCredentials.screenScraperPreferredRegion

    private var isLoggedIn: Bool { MetadataCredentials.hasUserCredentials }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: isLoggedIn ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isLoggedIn ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isLoggedIn ? "Currently signed in" : "Not signed in")
                                .font(.headline)
                            if let name = MetadataCredentials.screenScraperUserID, isLoggedIn {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    Text(
                        "Sign in with your personal ScreenScraper account. These are sent as `ssid` and `sspassword` and may unlock higher API limits on your account."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Link("Create a ScreenScraper account", destination: URL(string: "https://www.screenscraper.fr/")!)
                }

                Section("Your ScreenScraper login") {
                    TextField("Username (ssid)", text: $userID)
                        .textContentType(.username)
                    SecureField("Password (sspassword)", text: $userPassword)
                        .textContentType(.password)
                }

                Section("Default game region") {
                    Picker("Cover region", selection: $preferredRegion) {
                        ForEach(ScreenScraperRegionPreference.selectableRegions, id: \.code) { region in
                            Text(region.label).tag(region.code)
                        }
                    }
                    Text(
                        "ScreenScraper cover art prefers this region. If a game has no art for that region, the app falls back to World, then other regions."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("ScreenScraper Login")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MetadataCredentials.screenScraperUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
                        MetadataCredentials.screenScraperUserPassword = userPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                        MetadataCredentials.screenScraperPreferredRegion = preferredRegion
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

#Preview {
    ScreenScraperSettingsSheet()
}
