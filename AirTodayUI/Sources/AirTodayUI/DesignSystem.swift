import SwiftUI

/// Centralized design tokens for consistent visual language.
public enum DS {
    // MARK: - Opacity

    /// Primary text/icons on atmosphere background
    public static let opacityPrimary = 0.9
    /// Secondary text (labels, descriptions)
    public static let opacitySecondary = 0.7
    /// Tertiary text (hints, captions)
    public static let opacityTertiary = 0.5
    /// Quaternary text (timestamps, minor details)
    public static let opacityQuaternary = 0.4
    /// Faintest elements (scroll hints, inactive dots)
    public static let opacityHint = 0.3
    /// Standard divider/separator opacity
    public static let opacityDivider = 0.15

    // MARK: - Spacing

    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 12
    public static let spacingLG: CGFloat = 16
    public static let spacingXL: CGFloat = 20
    public static let spacingXXL: CGFloat = 32

    // MARK: - Corner Radius

    public static let cornerRadius: CGFloat = 16
    public static let cornerRadiusSM: CGFloat = 12
    public static let cornerRadiusXS: CGFloat = 6

    // MARK: - Icon Sizes

    public static let iconSM: CGFloat = 18
    public static let iconMD: CGFloat = 24
    public static let iconLG: CGFloat = 36

    // MARK: - Card Header Padding

    /// Standard card header: horizontal + top 12 + bottom 8
    public static let cardHeaderTop: CGFloat = 12
    public static let cardHeaderBottom: CGFloat = 8

    /// App-only preference: turns off haze, particles, parallax and swipe lag.
    public static let reduceVisualEffectsKey = "reduce_visual_effects"

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
    }

    // MARK: - Text Shadows

    /// Strong shadow for text over atmosphere gradients
    public static func atmosphereShadow(_ content: some View) -> some View {
        content
            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    // MARK: - Card Background

    public static var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black.opacity(0.15))
            }
    }

    // MARK: - Divider

    public static var divider: some View {
        Rectangle()
            .fill(.white.opacity(opacityDivider))
            .frame(height: 0.5)
    }
}
