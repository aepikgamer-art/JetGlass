import SwiftUI

@main
struct JetGlassApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
        }
    }
}

// MARK: - Settings

final class AppSettings: ObservableObject {
    @AppStorage("apiBaseURL") var apiBaseURL: String = "https://www.jetapi.dev"
    @AppStorage("photoCount") var photoCount: Int = 12
    @AppStorage("flightCount") var flightCount: Int = 12
    @AppStorage("mapRefreshSeconds") var mapRefreshSeconds: Double = 12
    @AppStorage("showAirlineLabels") var showAirlineLabels: Bool = true
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true
}
