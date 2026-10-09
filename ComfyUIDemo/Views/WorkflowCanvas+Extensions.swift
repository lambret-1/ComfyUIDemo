import SwiftUI
import UIKit

// MARK: - 数组安全下标

extension Array {
    /// 安全下标访问：越界返回 nil 而非崩溃
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 节点渲染数据预计算缓存

/// 节点渲染数据缓存：避免每帧重复计算 nodeSize、插槽位置、截断文本等
/// 仅在 workflow 结构变化时重建，拖动节点时缓存仍然有效
struct NodeRenderData {
    /// 节点尺寸
    let nodeSize: CGSize
    /// 标题栏高度
    let headerHeight: CGFloat
    /// 输出插槽Y偏移（相对节点顶部，用于快速定位插槽圆点）
    let outputSlotYOffsets: [CGFloat]
    /// 输入插槽Y偏移（相对节点顶部）
    let inputSlotYOffsets: [CGFloat]
    /// 预本地化+截断的输出插槽名称
    let outputSlotNames: [String]
    /// 预本地化+截断的输入插槽名称
    let inputSlotNames: [String]
    /// 预本地化+截断的控件标签文本
    let widgetLabels: [String]
    /// 节点显示标题
    let displayTitle: String
    /// 节点类型标签文本
    let typeLabel: String
}

// MARK: - 高性能文本绘制与渲染缓存辅助

extension WorkflowCanvasView {

    // MARK: - NSAttributedString 直接绘制

    /// 在 GraphicsContext 中直接绘制 NSAttributedString
    /// 比 context.draw(Text(...)) 快 5~10 倍（无需每次解析 SwiftUI Text 视图树）
    func drawAttributed(_ attrString: NSAttributedString, in rect: CGRect, context: GraphicsContext) {
        guard rect.width > 0, rect.height > 0, attrString.length > 0 else { return }
        context.withCGContext { cgContext in
            cgContext.saveGState()
            UIGraphicsPushContext(cgContext)
            attrString.draw(in: rect)
            UIGraphicsPopContext()
            cgContext.restoreGState()
        }
    }

    /// 在 GraphicsContext 中直接绘制纯文本（指定字体、颜色、对齐方式）
    func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                  alignment: NSTextAlignment = .left, context: GraphicsContext) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let paragraphStyle = paragraph
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        drawAttributed(attrString, in: rect, context: context)
    }

    /// 在指定点绘制文本（支持锚点对齐：.leading/.trailing/.center 等）
    func drawTextAtPoint(_ text: String, at point: CGPoint, font: UIFont, color: UIColor,
                         anchor: UnitPoint, context: GraphicsContext) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()

        // 根据锚点计算绘制矩形原点
        var origin = point
        if anchor == .trailing {
            origin = CGPoint(x: point.x - textSize.width, y: point.y - textSize.height / 2)
        } else if anchor == .leading {
            origin = CGPoint(x: point.x, y: point.y - textSize.height / 2)
        } else if anchor == .center {
            origin = CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2)
        } else if anchor == .topLeading {
            origin = point
        } else if anchor == .topTrailing {
            origin = CGPoint(x: point.x - textSize.width, y: point.y)
        }

        let rect = CGRect(origin: origin, size: textSize)
        drawAttributed(attrString, in: rect, context: context)
    }

    // MARK: - 节点位置计算（含拖动偏移）

    /// 获取节点的有效绘制位置：拖动中使用 pos + draggingOffset，否则直接用 pos
    func effectivePosition(for node: NodeModel) -> CGPoint {
        if node.id == draggingNodeId {
            return CGPoint(x: node.position.x + draggingOffset.width,
                           y: node.position.y + draggingOffset.height)
        }
        return node.position
    }

    // MARK: - 渲染缓存构建

    /// 为单个节点构建渲染缓存数据
    func buildRenderData(for node: NodeModel) -> NodeRenderData {
        let size = node.nodeSize
        let headerHeight = min(30, size.height * 0.4)
        let slotGap: CGFloat = 20
        let slotAreaTop: CGFloat = headerHeight + 8

        // 输出插槽 Y 偏移与名称
        var outputYOffsets: [CGFloat] = []
        var outputNames: [String] = []
        if let outputs = node.outputs {
            let labelFont = UIFont.systemFont(ofSize: 9)
            for (index, slot) in outputs.enumerated() {
                outputYOffsets.append(slotAreaTop + CGFloat(index) * slotGap)
                if let name = slot.name, !name.isEmpty {
                    let localized = SlotLocalization.localized(for: name)
                    outputNames.append(truncatedText(localized, font: labelFont, maxWidth: 70))
                } else {
                    outputNames.append("")
                }
            }
        }

        // 输入插槽 Y 偏移与名称
        var inputYOffsets: [CGFloat] = []
        var inputNames: [String] = []
        if let inputs = node.inputs {
            let labelFont = UIFont.systemFont(ofSize: 9)
            for (index, slot) in inputs.enumerated() {
                inputYOffsets.append(slotAreaTop + CGFloat(index) * slotGap)
                if let name = slot.name, !name.isEmpty {
                    let localized = SlotLocalization.localized(for: name)
                    inputNames.append(truncatedText(localized, font: labelFont, maxWidth: 90))
                } else {
                    inputNames.append("")
                }
            }
        }

        // 控件标签（预本地化 + 截断）
        var widgetLabels: [String] = []
        let widgetCount = node.widgetsValues?.count ?? 0
        if widgetCount > 0 {
            let labelFont = UIFont.systemFont(ofSize: 8)
            let names = node.widgetNames
            for i in 0..<widgetCount {
                let rawName = i < names.count ? names[i] : "参数\(i + 1)"
                let localized = SlotLocalization.localized(for: rawName)
                widgetLabels.append(truncatedText(localized, font: labelFont, maxWidth: 44))
            }
        }

        // 节点类型标签：UUID型节点（长度>30且包含连字符）隐藏类型标签，避免显示冗长UUID
        let typeLabel: String = {
            if node.type.count > 30 && node.type.contains("-") {
                return ""
            }
            return node.type
        }()

        return NodeRenderData(
            nodeSize: size,
            headerHeight: headerHeight,
            outputSlotYOffsets: outputYOffsets,
            inputSlotYOffsets: inputYOffsets,
            outputSlotNames: outputNames,
            inputSlotNames: inputNames,
            widgetLabels: widgetLabels,
            displayTitle: node.displayTitle,
            typeLabel: typeLabel
        )
    }

    /// 重建所有节点的渲染缓存（workflow 结构变化时调用）
    func rebuildRenderCache() {
        var cache: [Int: NodeRenderData] = [:]
        for node in workflow.nodes {
            cache[node.id] = buildRenderData(for: node)
        }
        renderCache = cache
    }
}
