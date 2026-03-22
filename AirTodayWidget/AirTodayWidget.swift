import WidgetKit
import SwiftUI
import AirTodayCore

@main
struct AirTodayWidgetBundle: WidgetBundle {
    var body: some Widget {
        AQIWidget()
    }
}

struct AQIWidget: Widget {
    let kind = "com.airtoday.widget.aqi"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AQIWidgetProvider()) { entry in
            AQIWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    // Only system families get the rich background.
                    // Accessory widgets must use the system-provided background per HIG.
                    ZStack {
                        Image(entry.level.backgroundImageName)
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
        .configurationDisplayName("Air Quality")
        .description("Current AQI at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}
