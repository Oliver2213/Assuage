import SwiftUI

/// Publishes the active window's `AppModel` as a focused scene value, so the
/// menu-bar commands act on whichever window is frontmost (each window has its
/// own `AppModel` now). Set with `.focusedSceneValue(\.appModel, model)` on the
/// window root; read with `@FocusedValue(\.appModel)` in `Commands`.
private struct AppModelFocusedValueKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var appModel: AppModel? {
        get { self[AppModelFocusedValueKey.self] }
        set { self[AppModelFocusedValueKey.self] = newValue }
    }
}
