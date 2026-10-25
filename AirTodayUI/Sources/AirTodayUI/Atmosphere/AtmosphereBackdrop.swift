import SwiftUI
import AirTodayCore

/// One continuous atmosphere behind every location page.
///
/// Everything follows the swipe position continuously: each page's photo (with its
/// own time-of-day tint) moves at a fraction of the swipe and crossfades with its
/// neighbour, and haze and particles blend between the two cities. Nothing switches
/// at the halfway point, so swiping back and forth never pops. Vertically, each
/// photo drifts with its own page's scroll (parallax), clamped so it never runs out.
struct AtmosphereBackdrop: View {
    struct Layer: Identifiable {
        let id: UUID
        let level: AQILevel
        let params: AtmosphereParameters
        /// That page's vertical scroll offset.
        let scrollOffset: CGFloat
    }

    let layers: [Layer]
    /// Fractional index of the horizontal pager (1.5 = halfway between pages 1 and 2).
    let pagePosition: CGFloat
    /// True while the visible page is refreshing; particles brighten and breathe.
    let isStirred: Bool
    let parallaxEnabled: Bool
    /// False under Reduce Motion or Reduce Visual Effects: no particles, no parallax,
    /// no swipe lag, and the haze holds still.
    let motionEnabled: Bool
    /// False under Reduce Visual Effects: no haze shader or particles at all.
    let effectsEnabled: Bool
    let tier: RenderQuality.QualityTier

    /// Share of the swipe distance the photos travel. Small, so it reads as lag, not motion.
    private static let swipeLag: CGFloat = 0.2
    /// Vertical parallax speed relative to scrolling.
    private static let scrollParallax: CGFloat = 0.35
    /// Extra photo height available for vertical parallax, as a share of the screen.
    private static let parallaxHeadroom: CGFloat = 0.35

    /// Where the swipe is: the page underneath, and how far the next one has faded in.
    private var swipe: (lower: Int, blend: CGFloat, position: CGFloat) {
        let maxIndex = CGFloat(max(layers.count - 1, 0))
        // Rubber-band overscroll past the first/last page shouldn't reveal empty space.
        let position = min(max(pagePosition, 0), maxIndex)
        let lower = Int(position.rounded(.down))
        return (lower, position - CGFloat(lower), position)
    }

    /// Haze and particles part-way between the two cities on screen.
    private var blendedParams: AtmosphereParameters {
        guard !layers.isEmpty else { return .placeholder }
        let (lower, blend, _) = swipe
        let base = layers[lower].params
        guard blend > 0, lower + 1 < layers.count else { return base }
        return base.blended(with: layers[lower + 1].params, fraction: Double(blend))
    }

    var body: some View {
        let params = blendedParams

        GeometryReader { geo in
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1)

                photos(in: geo.size)

                // Soft blur + darken scrim for text readability
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.35)

                // Gradient scrim — darker at top for status bar / hero text readability
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.6), .black.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 350)
                    Spacer()
                }

                if effectsEnabled && tier.shadersEnabled {
                    ShaderOverlay(params: params, isAnimated: motionEnabled)
                        .opacity(0.4)

                    if motionEnabled {
                        ParticleOverlay(config: params.particleConfig, tier: tier, isStirred: isStirred)
                            .opacity(0.5)
                    }
                }
            }
            .compositingGroup()
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Time of Day

    /// Warm around the station's sunrise and sunset, cool and darker at night.
    @ViewBuilder
    private func skyTint(_ dayPhase: DayPhase) -> some View {
        switch dayPhase {
        case .day:
            Color.clear
        case .golden(let intensity):
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.55 * intensity),
                    Color(red: 1.0, green: 0.7, blue: 0.45).opacity(0.25 * intensity),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .blendMode(.softLight)
        case .night:
            Color(red: 0.05, green: 0.09, blue: 0.25)
                .opacity(0.5)
                .blendMode(.multiply)
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private func photos(in size: CGSize) -> some View {
        let swipeLag = motionEnabled ? Self.swipeLag : 0
        let (lower, blend, position) = swipe

        // Lower page underneath at full opacity, next page fading in on top, so the
        // pair always covers the screen mid-swipe. The pages either side stay in the
        // hierarchy (invisible) so a swipe in either direction starts with its photo
        // already loaded, rather than inserting a full-screen image as the finger moves.
        ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
            if (lower - 1)...(lower + 2) ~= index {
                ZStack {
                    LevelPhoto(level: layer.level)
                    // Animate the tint alone: an animation on the whole layer would make
                    // its position and opacity trail the finger whenever the phase changes.
                    skyTint(layer.params.dayPhase)
                        .animation(DS.Motion.atmospheric, value: layer.params.dayPhase)
                }
                .compositingGroup()
                .frame(
                    width: size.width * (1 + 2 * swipeLag),
                    height: size.height * (1 + Self.parallaxHeadroom)
                )
                .position(
                    x: size.width / 2 - (position - CGFloat(index)) * size.width * swipeLag,
                    y: size.height * (1 + Self.parallaxHeadroom) / 2 - verticalShift(layer.scrollOffset, height: size.height)
                )
                .opacity(index == lower ? 1 : index == lower + 1 ? blend : 0)
            }
        }
    }

    private func verticalShift(_ scrollOffset: CGFloat, height: CGFloat) -> CGFloat {
        guard parallaxEnabled && motionEnabled else { return 0 }
        return min(max(0, scrollOffset) * Self.scrollParallax, height * Self.parallaxHeadroom)
    }
}

/// The level's photo, crossfading when the level changes.
private struct LevelPhoto: View {
    let level: AQILevel

    var body: some View {
        ZStack {
            Image(level.backgroundImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .id(level)
                .transition(.opacity)
        }
        .clipped()
        .animation(DS.Motion.atmospheric, value: level)
    }
}
