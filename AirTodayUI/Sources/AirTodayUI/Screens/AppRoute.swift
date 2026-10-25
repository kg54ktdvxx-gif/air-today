import Foundation

/// Every screen pushed onto the main NavigationStack.
///
/// One typed route resolved by a single `navigationDestination` at the stack root —
/// SwiftUI only honours the root-most destination for a given type, so screens
/// further down must not declare their own.
enum AppRoute: Hashable {
    case settings
    case privacyPolicy
}
