import SwiftUI

// MARK: - Liquid Glass helpers (iOS 26)

struct GlassCard: ViewModifier {
    @State private var animate = false
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Root

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: Tab = .map

    enum Tab: Hashable { case map, photos, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            LiveMapView(openPhotosFor: { query in
                PhotoSearch.shared.pendingQuery = query
                selectedTab = .photos
            })
            .tabItem { Label("Map", systemImage: "map") }
            .tag(Tab.map)

            PhotosView()
            .tabItem { Label("Photos", systemImage: "photo.stack") }
            .tag(Tab.photos)

            SettingsView()
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .tint(.cyan)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Tiny shim so the map can hand a registration to the Photos tab.
final class PhotoSearch: ObservableObject {
    static let shared = PhotoSearch()
    @Published var pendingQuery: String?
    private init() {}
}
