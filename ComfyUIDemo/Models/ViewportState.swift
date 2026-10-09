import CoreGraphics

/// 视口状态：管理画布的缩放和平移
struct ViewportState: Equatable {
    /// 当前缩放比例
    var scale: CGFloat = 1.0
    /// 当前偏移量（屏幕坐标系）
    var offset: CGPoint = .zero
    /// 上一次缩放结束时的缩放比例（用于手势计算）
    var lastScale: CGFloat = 1.0
    /// 上一次平移结束时的偏移量（用于手势计算）
    var lastOffset: CGPoint = .zero

    /// 世界坐标转屏幕坐标
    func toScreen(_ worldPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: worldPoint.x * scale + offset.x,
            y: worldPoint.y * scale + offset.y
        )
    }

    /// 屏幕坐标转世界坐标
    func toWorld(_ screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - offset.x) / scale,
            y: (screenPoint.y - offset.y) / scale
        )
    }

    /// 应用平移增量（屏幕坐标系）
    mutating func applyPan(translation: CGSize) {
        offset = CGPoint(
            x: lastOffset.x + translation.width,
            y: lastOffset.y + translation.height
        )
    }

    /// 应用缩放量（相对于lastScale）
    mutating func applyZoom(magnification: CGFloat, minScale: CGFloat, maxScale: CGFloat) {
        scale = min(max(lastScale * magnification, minScale), maxScale)
    }

    /// 手势结束时保存当前状态
    mutating func saveState() {
        lastScale = scale
        lastOffset = offset
    }
}
