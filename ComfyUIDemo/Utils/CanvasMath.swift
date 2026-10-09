import SwiftUI

/// 画布数学计算工具：包围盒、适配缩放、边界钳位
enum CanvasMath {
    /// 最小缩放比例（超大工作流时防止缩到看不见）
    static let minZoom: CGFloat = 0.1
    /// 最大缩放比例（单节点时防止过度放大）
    static let maxZoom: CGFloat = 1.5
    /// 适配时预留的边距比例
    static let fitPadding: CGFloat = 0.9

    /// 计算所有节点的包围盒
    static func getBoundingBox(nodes: [NodeModel]) -> CGRect {
        guard !nodes.isEmpty else { return .zero }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for node in nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 计算使整个工作流适配视图的缩放比例，并钳位到 [minZoom, maxZoom]
    static func computeFitScale(box: CGRect, viewSize: CGSize) -> CGFloat {
        guard box.width > 0, box.height > 0 else { return 1.0 }
        let sx = (viewSize.width * fitPadding) / box.width
        let sy = (viewSize.height * fitPadding) / box.height
        let fit = min(sx, sy)
        return clamp(fit, min: minZoom, max: maxZoom)
    }

    /// 通用钳位函数
    static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
