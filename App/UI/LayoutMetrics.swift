import CoreGraphics
import Foundation

/// Sizes that two files each have to agree on: a window/panel/popover
/// that reserves the space, and the SwiftUI view that draws into it.
/// They live here rather than as a private constant in each file because
/// nothing else forces them to match — a divergence produces no build
/// error and no runtime warning, only silently clipped content.
///
/// That is not hypothetical. The popover pair has already caused it
/// once: content clipped against the smaller of the two values with no
/// scroll indicator to reveal that anything was missing.

enum NotchMetrics {
    /// The expanded verse/prayer-alert card: `NotchController` sizes the
    /// panel window to this, `NotchContentView` sizes its content to it.
    ///
    /// Growing the height is safe. Shrinking it is not, on its own: the
    /// card's top inset must stay at least the *live* collapsed notch
    /// height (`NotchViewModel.collapsedSize.height`, derived from this
    /// Mac's real `safeAreaInsets.top`), because that band is physically
    /// occluded by the camera housing rather than merely padded. Reclaim
    /// text space by growing this height, never by trimming that inset.
    static let expandedSize = CGSize(width: 480, height: 220)
}

enum PopoverMetrics {
    /// The Settings popover: `StatusItemController` sets
    /// `popover.contentSize` from this, `PopoverContentView` frames
    /// itself to it. The content scrolls, so this is a viewport size —
    /// but only the view's own `ScrollView` scrolls, not the popover, so
    /// a value larger here than there still clips.
    static let contentSize = CGSize(width: 320, height: 620)
}
