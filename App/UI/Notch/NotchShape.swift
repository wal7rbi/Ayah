import SwiftUI

/// Concave-top notch silhouette adapted from DynamicNotchKit by Kai Azim.
/// Original: Sources/DynamicNotchKit/Views/NotchShape.swift at revision
/// cd0b3e52d537db115ad3a9d89601f20e0bee8d27 (MIT, copyright 2025 Kai Azim).
/// The same path implementation was encountered in TheBoredTeam/boring.notch,
/// which credits DynamicNotchKit. Verified against the original MIT source;
/// see Resources/ThirdParty/DynamicNotchKit-LICENSE.txt and THIRD_PARTY_LICENSES.md.
struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
