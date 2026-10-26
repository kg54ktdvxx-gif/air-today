import SwiftUI
import AirTodayCore

/// The activities, grouped by what they share — "All activities: Great" on a clean
/// day, a row per distinct recommendation otherwise — with the best time, today's
/// outlook and the advice's basis as a footer. The verdict itself is the hero's.
public struct ActivityGuidanceCard: View {
    let guidance: ActivityGuidance
    /// The chosen scale, which the advice follows.
    let scale: AQIScale
    /// The scale on screen (US EPA when the chosen one needs model data that's missing),
    /// whose colours the recommendations take.
    let shownScale: AQIScale
    @State private var showingAbout = false
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(guidance: ActivityGuidance, scale: AQIScale, shownScale: AQIScale) {
        self.guidance = guidance
        self.scale = scale
        self.shownScale = shownScale
    }

    /// Activities sharing a recommendation and reason, in the order they're listed.
    struct Group: Identifiable {
        let recommendation: Rec
        let reason: String
        let activities: [Activity]
        var id: String { "\(recommendation.rawValue)|\(reason)" }

        var title: String {
            activities.count == Activity.allCases.count
                ? "All activities"
                : ListFormatter.localizedString(byJoining: activities.map(\.displayName))
        }
    }

    static func groups(_ recs: [ActivityRec]) -> [Group] {
        var order: [String] = []
        var members: [String: (Rec, String, [Activity])] = [:]
        for rec in recs.sorted(by: { $0.recommendation < $1.recommendation }) {
            let key = "\(rec.recommendation.rawValue)|\(rec.reason)"
            if members[key] == nil { order.append(key); members[key] = (rec.recommendation, rec.reason, []) }
            members[key]?.2.append(rec.activity)
        }
        return order.compactMap { members[$0] }.map { Group(recommendation: $0.0, reason: $0.1, activities: $0.2) }
    }

    public var body: some View {
        let groups = Self.groups(guidance.activities)

        VStack(alignment: .leading, spacing: 0) {
            Text("Activities")
                .font(DS.Typeface.cardTitle)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.spacingLG)
                .padding(.top, DS.cardHeaderTop)
                .padding(.bottom, DS.spacingXS)
                .accessibilityAddTraits(.isHeader)

            ForEach(groups) { group in
                groupRow(group)

                if group.id != groups.last?.id {
                    DS.divider
                        .padding(.horizontal, DS.spacingLG)
                }
            }

            footer
        }
        .background { DS.cardBackground }
        .sheet(isPresented: $showingAbout) {
            AdviceInfoSheet(scale: scale)
        }
    }

    private func groupRow(_ group: Group) -> some View {
        // Side by side, or stacked when the text is too large to share a line.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.spacingXS))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.spacingMD))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(DS.Typeface.rowTitle)
                    .foregroundStyle(.white)
                Text(group.reason)
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.white.opacity(DS.opacitySecondary))
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: DS.spacingSM)
            }

            HStack(spacing: 6) {
                DS.colorDot(shownScale.color(for: group.recommendation.level))
                Text(group.recommendation.label)
                    .font(DS.Typeface.captionStrong)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.vertical, DS.spacingSM)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        // The best window is the place's, so it's the same for every activity.
        let bestWindow = guidance.activities.compactMap(\.bestWindow).first

        return VStack(alignment: .leading, spacing: DS.spacingSM) {
            DS.divider

            if let bestWindow {
                Label(bestWindow, systemImage: "clock")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
            }

            if let outlook = guidance.peakWarning {
                Label(outlook, systemImage: "chart.xyaxis.line")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(.white.opacity(DS.opacityPrimary))
            }

            Button {
                showingAbout = true
            } label: {
                Text("General guidance, not medical advice. \(Text("About this advice").underline())")
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                .font(DS.Typeface.fine)
                .foregroundStyle(.white.opacity(DS.opacityTertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("General guidance, not medical advice. About this advice")
        }
        .padding(.horizontal, DS.spacingLG)
        .padding(.bottom, DS.spacingMD)
        .padding(.top, DS.spacingXS)
    }
}
