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
                        ProgressView("Searching…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let error = searchError {
                    ContentUnavailableView {
                        Label("Search didn't work", systemImage: "wifi.exclamationmark")
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
                        "No stations found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another city or station name.")
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
                                VStack(alignment: .leading, spacing: DS.spacingXXS) {
                                    Text(station.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                if let aqi = station.aqi {
                                    Text("\(aqi)")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(AQILevel(aqi: aqi).color)
                                } else {
                                    Text("Offline")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .opacity(station.isOffline ? 0.5 : 1)
                        }
                        .accessibilityHint(station.isOffline ? "This station isn't reporting right now" : "")
                        .sensoryFeedback(.impact(flexibility: .solid), trigger: results.count)
                    }
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LocationSearchField(query: $query) {
                searchTask?.cancel()
                Task { await search() }
            })
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
            searchError = error is URLError
                ? UserFacingError.message(for: error)
                : "Search isn't working right now. Try again in a minute."
            results = []
        }
        isSearching = false
    }

    private func addStation(_ station: StationSummary) {
        let location = SavedLocation(
            name: station.name,
            coordinate: station.coordinate,
            stationID: station.id
        )
        locationManager.addLocation(location)
        dismiss()
    }
}

/// The sheet's search field: the system search bar, or on a Mac a plain text field.
///
/// The iPad app on a Mac can't use `.searchable`. Laying out UISearchController's
/// presentation sizes the bar with `UINavigationBar.defaultSize(for:)`, which on a Mac asks
/// UIScreen for the main scene's bounds through the focus system — and in apps built with
/// the iOS 27 SDK that throws ("Accessing the focus system through UIScreen is no longer
/// supported"), quitting the app as soon as the field is clicked. Every placement and
/// presentation behaviour goes the same way.
private struct LocationSearchField: ViewModifier {
    @Binding var query: String
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    private static let prompt: LocalizedStringKey = "Search cities or stations"

    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            content.safeAreaInset(edge: .top, spacing: 0) {
                field
            }
        } else {
            content
                .searchable(text: $query, prompt: Self.prompt)
                .onSubmit(of: .search, onSubmit)
        }
    }

    private var field: some View {
        HStack(spacing: DS.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(Self.prompt, text: $query)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.spacingMD)
        .padding(.vertical, DS.spacingSM)
        .background(.fill.tertiary, in: .rect(cornerRadius: DS.cornerRadiusSM))
        .padding(.horizontal, DS.spacingLG)
        .padding(.bottom, DS.spacingSM)
        .background(.bar)
        // A Mac has a keyboard; the sheet is opened to type in.
        .onAppear { isFocused = true }
    }
}
