import WidgetKit
import SwiftUI
import AirTodayCore

@main
struct AirTodayWidgetBundle: WidgetBundle {
    var body: some Widget {
        AQIWidget()
        ActivityCheckWidget()
        BestWindowWidget()
    }
}

struct AQIWidget: Widget {
    let kind = "com.airtoday.widget.aqi"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AirQualityWidgetIntent.self, provider: AQIWidgetProvider()) { entry in
            AQIWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPhotoBackground(level: entry.level)
                }
        }
        .configurationDisplayName("Air Quality")
        .description("Today's verdict and air quality where you are.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

/// The level's photo with the app's readability scrims. Only system families
/// draw it; accessory widgets use the system background per HIG.
struct WidgetPhotoBackground: View {
    let level: AQILevel

    var body: some View {
        ZStack {
            Image(level.backgroundImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)

            // Soft blur + darken for text readability
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.4)

            // Gradient scrim
            LinearGradient(
                colors: [.black.opacity(0.4), .black.opacity(0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
