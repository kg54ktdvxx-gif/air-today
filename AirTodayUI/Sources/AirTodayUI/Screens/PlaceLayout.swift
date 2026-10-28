import SwiftUI

/// How a place's hero and cards share the space a page has.
///
/// Chosen once per size by `LocationPager` and handed to every page, so the pages and
/// what's drawn behind and over them agree. The space available decides, never the
/// device: two panes need room for two columns of cards, and a fold, when there is
/// one, is where the layout divides, so bending the device moves nothing.
enum PlaceLayout: Equatable {
    /// One column: the hero, then the cards below it. `heroHeight` ends the hero above a
    /// horizontal fold and `foldGap` keeps the first card clear of it; a nil height is a
    /// hero the full height of the page.
    case column(heroHeight: CGFloat?, foldGap: CGFloat)
    /// The hero beside the cards. `heroWidth` is the hero pane's width and `gap` the space
    /// between the panes: the fold itself when the display has one.
    case panes(heroWidth: CGFloat, gap: CGFloat)

    static let fullHeightColumn = PlaceLayout.column(heroHeight: nil, foldGap: 0)

    /// - Parameter proxy: the space the pages fill, inside the safe area.
    static func resolve(in proxy: GeometryProxy, sizeClass: UserInterfaceSizeClass?) -> PlaceLayout {
        let size = proxy.size
        // Bent or not: an inactive fold still has a frame, so a layout built around it
        // doesn't jump when the device folds.
        let fold = proxy.fold(includeInactive: true)

        if sizeClass == .regular, size.width >= 2 * DS.cardMinWidth + DS.spacingXL {
            if let fold, fold.height > fold.width,
               fold.minX >= DS.cardMinWidth, size.width - fold.maxX >= DS.cardMinWidth {
                return .panes(heroWidth: fold.minX, gap: fold.width)
            }
            // No fold reported (the iPhone Duo simulator never reports one, flat or bent):
            // divide at the middle of the scene, where the fold is, not the middle of the
            // page, which a bar down one side moves off it. Unless a pane would get too narrow.
            let heroWidth = Self.sceneMiddle(in: proxy) - DS.spacingXL / 2
            if heroWidth >= DS.cardMinWidth, size.width - heroWidth - DS.spacingXL >= DS.cardMinWidth {
                return .panes(heroWidth: heroWidth, gap: DS.spacingXL)
            }
            return .panes(heroWidth: (size.width - DS.spacingXL) / 2, gap: DS.spacingXL)
        }
        if let fold, fold.width > fold.height, fold.minY > 0, fold.maxY < size.height {
            return .column(heroHeight: fold.minY, foldGap: fold.height)
        }
        return .fullHeightColumn
    }

    /// The middle of the scene, measured from the pages' leading edge. The pages fill the
    /// safe area, so the scene reaches past them by its insets. On iPhone Duo the system's
    /// vertical bar is one of those insets: it sits outside even the app's root view, so no
    /// view of ours can measure it any other way.
    private static func sceneMiddle(in proxy: GeometryProxy) -> CGFloat {
        let insets = proxy.safeAreaInsets
        return (insets.leading + proxy.size.width + insets.trailing) / 2 - insets.leading
    }

    /// Names the mode for UI tests, which can't otherwise tell a column from panes. An
    /// identifier, so VoiceOver never reads it.
    var accessibilityIdentifier: String {
        switch self {
        case .column: "place.column"
        case .panes: "place.panes"
        }
    }
}

extension GeometryProxy {
    /// The fold across this space, if the display has one. Only while the device is bent,
    /// unless `includeInactive`.
    func fold(includeInactive: Bool) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        return reservedRegions(kind: .division, options: includeInactive ? .includeInactive : [])
            .map(\.frame)
            .first { $0.intersects(bounds) }
    }
}

/// One side of a two-pane layout.
enum PlacePane {
    case hero, cards
}

extension View {
    /// Keeps the view within one pane when the hero and cards are side by side, so
    /// nothing that sits over the pages straddles the gap between them (the fold).
    func within(_ pane: PlacePane, of layout: PlaceLayout) -> some View {
        modifier(PaneFrame(pane: pane, layout: layout))
    }
}

private struct PaneFrame: ViewModifier {
    let pane: PlacePane
    let layout: PlaceLayout

    func body(content: Content) -> some View {
        switch layout {
        case .column:
            content
        case .panes(let heroWidth, let gap):
            HStack(spacing: 0) {
                switch pane {
                case .hero:
                    content.frame(width: heroWidth)
                    Spacer(minLength: 0)
                case .cards:
                    Color.clear.frame(width: heroWidth + gap)
                    content.frame(maxWidth: .infinity)
                }
            }
        }
    }
}
