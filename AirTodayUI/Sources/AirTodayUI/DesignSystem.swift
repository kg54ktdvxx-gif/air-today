import SwiftUI

/// Centralized design tokens for consistent visual language.
public enum DS {
    // MARK: - Opacity

    /// Primary text/icons on atmosphere background
    public static let opacityPrimary = 0.9
    /// Secondary text (labels, descriptions)
    public static let opacitySecondary = 0.8
    /// Tertiary text (hints, captions)
    public static let opacityTertiary = 0.65
    /// Quaternary text (timestamps, minor details)
    public static let opacityQuaternary = 0.4
    /// Faintest elements (scroll hints, inactive dots)
    public static let opacityHint = 0.3
    /// Standard divider/separator opacity
    public static let opacityDivider = 0.15

    // MARK: - Spacing

    // The only spacing values: 0, 2, 4, 8, 12, 16, 24, 32, 40, 48. Nothing between them.
    public static let spacingXXS: CGFloat = 2
    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 12
    public static let spacingLG: CGFloat = 16
    public static let spacingXL: CGFloat = 24
    public static let spacingXXL: CGFloat = 32
    public static let spacingXXXL: CGFloat = 40
    public static let spacingHuge: CGFloat = 48
    /// Below the last card, so the attribution clears the home indicator.
    public static let spacingPageEnd: CGFloat = spacingXXXL

    /// Layout, not spacing: how far the hero's place name sits below the top of the
    /// screen, clearing the status bar and the top bar (Dynamic Island 59 + bar 44 + 8,
    /// rounded up to the 8 pt grid).
    public static let heroTopInset: CGFloat = 112

    /// The widest cards, tiles and banners get, so on iPad they stay a comfortable
    /// reading width instead of stretching edge to edge.
    public static let readableWidth: CGFloat = 600

    // MARK: - Corner Radius

    // A shape inside another, less than 32 pt in, takes the outer radius minus the
    // gap (only when that's over 2). Today nothing nests that closely: chips are
    // capsules, and buttons inside cards sit 16 pt in, which leaves 0.
    public static let cornerRadius: CGFloat = 16
    public static let cornerRadiusSM: CGFloat = 12
    public static let cornerRadiusXS: CGFloat = 6

    // MARK: - Icon Sizes

    public static let iconSM: CGFloat = 18
    public static let iconMD: CGFloat = 24
    public static let iconLG: CGFloat = 36

    // MARK: - Type

    /// The app's few text styles. All SF Pro, so they scale with Dynamic Type; the
    /// one exception is the hero's numeral, in SF Pro Rounded.
    public enum Typeface {
        /// A card's title.
        public static let cardTitle = Font.headline
        /// A row's main text, and a card's body copy.
        public static let body = Font.subheadline
        /// A row's title when a caption sits under it.
        public static let rowTitle = Font.subheadline.weight(.medium)
        /// Reasons, notes, chips and footers.
        public static let caption = Font.caption
        /// Short labels that carry a value or status: "Great", a best time.
        public static let captionStrong = Font.caption.weight(.semibold)
        /// Fine print: disclaimers and axis labels.
        public static let fine = Font.caption2
        /// An onboarding step's title.
        public static let stepTitle = Font.title.weight(.bold)
    }

    // MARK: - Card Header Padding

    /// Standard card header: horizontal + top 12 + bottom 8
    public static let cardHeaderTop: CGFloat = 12
    public static let cardHeaderBottom: CGFloat = 8

    /// App-only preference: turns off haze, particles, parallax and swipe lag.
    public static let reduceVisualEffectsKey = "reduce_visual_effects"
    /// How many times the app has launched; some first-run hints stop after a few.
    public static let launchCountKey = "launch_count"

    // MARK: - Motion

    /// The only three curves the app animates with, so every transition feels
    /// like part of the same world. Pick by what is moving, not by taste.
    public enum Motion {
        /// Direct responses to a touch: selection, toggles, page dots, pills.
        public static let quick = Animation.spring(response: 0.3, dampingFraction: 0.82)
        /// Content changing shape or value: expanding cards, the AQI number, steps.
        public static let standard = Animation.spring(response: 0.55, dampingFraction: 0.86)
        /// The atmosphere itself: backgrounds, colour, haze — slow, like weather.
        public static let atmospheric = Animation.easeInOut(duration: 1.4)
        /// Content arriving: decelerates into place, slow and soft, never a default curve.
        public static func entrance(delay: Double = 0) -> Animation {
            .timingCurve(0.16, 1, 0.3, 1, duration: 0.9).delay(delay)
        }
        /// A line or bar drawing on, like progress.
        public static let draw = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 1.1)
    }

    // MARK: - Glass

    /// The one glass every card and banner sits on: dark enough that white text reads
    /// over any sky, and no border.
    public static var cardBackground: some View {
        glass(in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    public static func glass(in shape: some Shape) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(.black.opacity(0.4)) }
    }

    /// The glass lifted: a chosen tile, or a primary button straight on the sky.
    public static func liftedGlass(in shape: some Shape) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(selectedFill) }
    }

    /// Fill for a selected chip or tile, and for buttons on the glass.
    public static let selectedFill = Color.white.opacity(0.2)
    /// Fill for an unselected chip.
    public static let chipFill = Color.white.opacity(0.08)

    /// A small dot in a band's colour, beside text that stays white — the band colours
    /// include dark reds and purples that don't read as text on the glass.
    public static func colorDot(_ color: Color, size: CGFloat = 8) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // MARK: - Divider

    public static var divider: some View {
        Rectangle()
            .fill(.white.opacity(opacityDivider))
            .frame(height: 0.5)
    }
}

public extension DS {
    /// A shadow colour leaning toward the sky behind it rather than pure black: the
    /// band's colour, nearly black. With no band yet, a deep blue night.
    static func shadowTint(_ band: Color? = nil) -> Color {
        (band ?? Color(.sRGB, red: 0.1, green: 0.16, blue: 0.3)).mix(with: .black, by: 0.8)
    }
}

public extension View {
    /// The one shadow for text straight on the sky, with no glass behind it: applied
    /// once to a whole block rather than per line, enough to lift white text off a
    /// bright photo without looking embossed. Tinted toward the sky's own colour.
    func skyTextShadow(tint: Color = DS.shadowTint()) -> some View {
        compositingGroup().shadow(color: tint.opacity(0.45), radius: 8, y: 1)
    }
}

// MARK: - Press

/// The one press response for custom tappable surfaces (rows, tiles, pills, the
/// number): a slight shrink and dim, so a tap feels physical. System buttons keep
/// their own.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Entrance

/// How a piece of content arrives: a short rise, from soft focus to sharp.
public enum RiseKind {
    /// Text, values and rows.
    case item
    /// A whole card, with its contents.
    case card

    var offset: CGFloat { self == .card ? DS.spacingXL : 10 }
    var blur: CGFloat { self == .card ? 6 : 4 }
    var scale: CGFloat { self == .card ? 0.985 : 1 }
}

private struct RiseIn: ViewModifier {
    let shown: Bool
    let kind: RiseKind

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : kind.offset)
            .scaleEffect(shown ? 1 : kind.scale)
            .blur(radius: shown ? 0 : kind.blur)
    }
}

/// Reveals a card the first time a fifth of it scrolls into view, then never again.
private struct RevealOnScroll: ViewModifier {
    let isEnabled: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .modifier(RiseIn(shown: shown || !isEnabled, kind: .card))
            .onScrollVisibilityChange(threshold: 0.2) { visible in
                guard visible, !shown else { return }
                withAnimation(DS.Motion.entrance()) { shown = true }
            }
    }
}

public extension View {
    /// Drawn at rest when `shown`, risen and softened when not; animate `shown`.
    func riseIn(_ shown: Bool, _ kind: RiseKind = .item) -> some View {
        modifier(RiseIn(shown: shown, kind: kind))
    }

    /// A card that rises in once, as it first scrolls into view. Pass false under
    /// Reduce Motion or reduced effects, and it simply sits in place.
    func revealOnScroll(_ isEnabled: Bool) -> some View {
        modifier(RevealOnScroll(isEnabled: isEnabled))
    }
}
