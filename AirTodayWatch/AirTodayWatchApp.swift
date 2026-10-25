import SwiftUI
import AirTodayCore

@main
struct AirTodayWatchApp: App {
    @State private var model = WatchAirModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView(model: model)
                .task {
                    model.requestLocationIfAllowed()
                    await model.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    model.reloadFromStore()
                    model.requestLocationIfAllowed()
                    Task { await model.refresh() }
                }
                .onChange(of: model.locationService.coordinate.map(Coordinate.init)) {
                    // First fix after launch: replace the iPhone's or IP-based reading.
                    Task { await model.refresh(force: true) }
                }
        }
    }
}
