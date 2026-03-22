import SwiftUI
import AirTodayCore

/// Search sheet for adding saved locations.
public struct LocationSearchView: View {
    let locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [StationSummary] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    private let service = AirQualityService(token: AppConstants.waqiToken)

    public init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    public var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView("Searching...")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let error = searchError {
                    ContentUnavailableView {
                        Label("Search Failed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            searchTask?.cancel()
                            searchError = nil
                            Task { await search() }
                        }
                    }
                    .listRowBackground(Color.clear)
                } else if hasSearched && results.isEmpty {
                    ContentUnavailableView(
                        "No Stations Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different city or station name")
                    )
                    .listRowBackground(Color.clear)
                } else if !hasSearched && results.isEmpty {
                    ContentUnavailableView(
                        "Search for a City",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Add locations to monitor air quality around the world")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(results) { station in
                        Button {
                            addStation(station)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                if let aqi = station.aqi {
                                    Text("\(aqi)")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(AQILevel(aqi: aqi).color)
                                }
                            }
                        }
                        .sensoryFeedback(.impact(flexibility: .solid), trigger: results.count)
                    }
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search cities or stations")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 2 else {
                    if trimmed.isEmpty {
                        results = []
                        hasSearched = false
                        searchError = nil
                    }
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await search()
                }
            }
            .onSubmit(of: .search) {
                searchTask?.cancel()
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        searchError = nil

        do {
            results = try await service.search(keyword: trimmed)
            hasSearched = true
        } catch {
            searchError = error.localizedDescription
            results = []
        }
        isSearching = false
    }

    private func addStation(_ station: StationSummary) {
        let location = SavedLocation(
            name: station.name,
            coordinate: station.coordinate
        )
        locationManager.addLocation(location)
        dismiss()
    }
}
