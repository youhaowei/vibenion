import SwiftUI

/// A pill that blends into the screen's top edge: top corners curve *inward*
/// (concave) to flow off the screen, bottom corners curve *outward* (convex)
/// to round into the body. Animatable across both radii.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = topCornerRadius
        let b = bottomCornerRadius

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Inward top-left curve.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))

        // Outward bottom-left curve.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))

        // Outward bottom-right curve.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))

        // Inward top-right curve.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

extension NSScreen {
    static var builtInOrMain: NSScreen {
        screens.first { $0.isBuiltIn } ?? main ?? screens[0]
    }

    var isBuiltIn: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(id) != 0
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// Width × height of the physical notch (or a fallback for non-notched displays).
    var notchSize: CGSize {
        guard hasNotch else {
            return CGSize(width: 220, height: 36)
        }
        let leftWidth = auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = auxiliaryTopRightArea?.width ?? 0
        let menuBarHeight = frame.maxY - visibleFrame.maxY
        return CGSize(
            width: max(0, frame.width - leftWidth - rightWidth) + 4,
            height: max(safeAreaInsets.top, menuBarHeight)
        )
    }
}
