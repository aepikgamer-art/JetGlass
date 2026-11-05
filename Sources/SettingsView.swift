import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var cacheCleared = false

    private let altDirect = URL(string:
        "https://altdirect.app/?url=https%3A%2F%2Fraw.githubusercontent.com%2Faepikgamer-art%2FJetGlass%2Fmain%2Faltstore-source.json")!
    private let ipaDownload = URL(string:
        "https://github.com/aepikgamer-art/JetGlass/releases/latest/download/JetGlass.ipa")!
    private let sourceLink = URL(string: "https://github.com/aepikgamer-art/JetGlass")!
    private let jetapiLink = URL(string: "https://www.jetapi.dev")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Base URL") {
                        TextField("https://www.jetapi.dev", text: $settings.apiBaseURL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper("Photos per search: \(settings.photoCount)",
                            value: $settings.photoCount, in: 1...24)
                    Stepper("Flights to fetch: \(settings.flightCount)",
                            value: $settings.flightCount, in: 1...30)
                } header: {
                    Text("JetAPI")
                } footer: {
                    Link("Source API: jetapi.dev", destination: jetapiLink)
                        .font(.caption)
                }

                Section("Live Map") {
                    Stepper("Refresh every \(Int(settings.mapRefreshSeconds))s",
                            value: $settings.mapRefreshSeconds, in: 5...60, step: 1)
                    Toggle("Show airline labels above planes",
                           isOn: $settings.showAirlineLabels)
                }

                Section {
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    Button("Clear image cache") {
                        URLCache.shared.removeAllCachedResponses()
                        cacheCleared = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            cacheCleared = false
                        }
                    }
                    if cacheCleared {
                        Text("Cache cleared ✓")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("General")
                }

                Section {
                    Link(destination: altDirect) {
                        Label("Add to AltStore via AltDirect", systemImage: "arrow.down.app")
                    }
                    Link(destination: ipaDownload) {
                        Label("Download latest IPA", systemImage: "square.and.arrow.down")
                    }
                    Link(destination: sourceLink) {
                        Label("Source on GitHub", systemImage: "curlybraces")
                    }
                } header: {
                    Text("Install & Source")
                } footer: {
                    Text("AltDirect opens the JetGlass AltStore source in AltStore, SideStore, StikStore, Feather and more. The IPA is built by GitHub Actions on macOS 26 (Xcode 26) and published to Releases.")
                        .font(.caption)
                }

                Section("About") {
                    LabeledContent("JetGlass", value: "v1.0.0")
                    LabeledContent("Map engine", value: "Apple Maps (MapKit)")
                    LabeledContent("Data", value: "jetapi.dev")
                    LabeledContent("Photos", value: "JetPhotos.com")
                    LabeledContent("Live traffic", value: "FlightRadar24")
                    Link("jetapi.dev documentation",
                         destination: URL(string: "https://www.jetapi.dev/documentation")!)
                }

                Section {
                    Text("Photos belong to their respective photographers on JetPhotos. "
                         + "This app is for personal spotting only — not affiliated with "
                         + "JetPhotos, FlightRadar24, or jetapi.dev.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
