import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var cacheCleared = false

    var body: some View {
        NavigationStack {
            Form {
                Section("JetAPI") {
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
                }

                Section("Live Map") {
                    Stepper("Refresh every \(Int(settings.mapRefreshSeconds))s",
                            value: $settings.mapRefreshSeconds, in: 5...60, step: 1)
                    Toggle("Show airline labels above planes",
                           isOn: $settings.showAirlineLabels)
                }

                Section("General") {
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
                }

                Section("About") {
                    LabeledContent("JetGlass", value: "v1.0.0")
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
