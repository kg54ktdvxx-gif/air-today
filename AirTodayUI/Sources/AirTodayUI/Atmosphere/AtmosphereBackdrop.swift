import SwiftUI
import AirTodayCore

/// One continuous atmosphere behind every location page.
///
/// Each page's photo moves at a fraction of the horizontal swipe, so the scene
/// lags behind the content like a camera panning across one landscape, and the
/// next page's photo crossfades in over it. Vertically, each photo drifts with
/// its own page's scroll (parallax), clamped so it never runs out.
struct AtmosphereBackdrop: View {
    struct Layer: Identifiable {
        let id: UUID
        let level: AQILevel
        /// That page's vertical scroll offset.
        let scrollOffset: CGFloat
    }

    let layers: [Layer]
    /// Fractional index of the horizontal pager (1.5 = halfway between pages 1 and 2).
    let pagePosition: CGFloat
    /// Atmosphere of the page nearest the centre, for haze and particles.
    let params: AtmosphereParameters
    /// True while the visible page is refreshing; particles brighten and breathe.
    let isStirred: Bool
    let parallaxEnabled: Bool
    let tier: RenderQuality.QualityTier

    /// Share of the swipe distance the photos travel. Small, so it reads as lag, not motion.
    private static let swipeLag: CGFloat = 0.2
    /// Vertical parallax speed relative to scrolling.
    private static let scrollParallax: CGFloat = 0.35
    /// Extra photo height available for vertical parallax, as a share of the screen.
    private static let parallaxHeadroom: CGFloat = 0.35

    var body: some View {
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

                if tier.shadersEnabled {
                    ShaderOverlay(params: params)
                        .opacity(0.4)

                    ParticleOverlay(config: params.particleConfig, tier: tier, isStirred: isStirred)
                        .opacity(0.5)
                }
            }
            .compositingGroup()
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Photos

    @ViewBuilder
    private func photos(in size: CGSize) -> some View {
        let maxIndex = CGFloat(max(layers.count - 1, 0))
        // Rubber-band overscroll past the first/last page shouldn't reveal empty space.
        let position = min(max(pagePosition, 0), maxIndex)
        let lower = Int(position.rounded(.down))
        let blend = position - CGFloat(lower)

        // Lower page underneath at full opacity, next page fading in on top,
        // so the pair always covers the screen mid-swipe.
        ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
            if index == lower || (index == lower + 1 && blend > 0) {
                LevelPhoto(level: layer.level)
                    .frame(
                        width: size.width * (1 + 2 * Self.swipeLag),
                        height: size.height * (1 + Self.parallaxHeadroom)
                    )
                    .position(
                        x: size.width / 2 - (position - CGFloat(index)) * size.width * Self.swipeLag,
                        y: size.height * (1 + Self.parallaxHeadroom) / 2 - verticalShift(layer.scrollOffset, height: size.height)
                    )
                    .opacity(index == lower ? 1 : blend)
            }
        }
    }

    private func verticalShift(_ scrollOffset: CGFloat, height: CGFloat) -> CGFloat {
        guard parallaxEnabled else { return 0 }
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
