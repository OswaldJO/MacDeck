import SwiftUI

/// Twitch Developer credentials for IGDB (same stack as Playnite’s IGDB metadata provider).
struct IGDBSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientId: String = MetadataCredentials.twitchClientId ?? ""
    @State private var clientSecret: String = MetadataCredentials.twitchClientSecret ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Create an app at Twitch Developer Console, enable IGDB access, then paste **Client ID** and **Client Secret** here. The app requests metadata in the background, similar to Playnite’s automatic metadata download."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Link("Twitch Developer Console", destination: URL(string: "https://dev.twitch.tv/console/apps")!)
                    Link("IGDB API docs", destination: URL(string: "https://api-docs.igdb.com")!)
                }

                Section("Credentials") {
                    TextField("Client ID", text: $clientId)
                        .textContentType(.username)
                    SecureField("Client Secret", text: $clientSecret)
                        .textContentType(.password)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Metadata (IGDB)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MetadataCredentials.twitchClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
                        MetadataCredentials.twitchClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 320)
    }
}

#Preview {
    IGDBSettingsSheet()
}
