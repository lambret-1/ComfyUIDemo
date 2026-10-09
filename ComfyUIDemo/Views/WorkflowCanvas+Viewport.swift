import SwiftUI

// MARK: - 视角适配模块

extension WorkflowCanvasView {

    /// 适配整个工作流到视图中央
    func fitToView(size: CGSize) {
        var allBoxes: [CGRect] = workflow.nodes.map {
            CGRect(origin: $0.position, size: $0.nodeSize)
        }
        allBoxes.append(contentsOf: workflow.groups.map { $0.frame })

        guard !allBoxes.isEmpty else {
            zoom = 1.0; offset = .zero; lastZoom = 1.0; lastOffset = .zero
            return
        }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for box in allBoxes {
            minX = min(minX, box.minX)
            minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        guard box.width > 0, box.height > 0 else {
            zoom = 1.0; offset = .zero; lastZoom = 1.0; lastOffset = .zero
            return
        }

        zoom = CanvasMath.computeFitScale(box: box, viewSize: size)
        lastZoom = zoom
        offset = CGPoint(
            x: size.width / 2 - (box.midX * zoom),
            y: size.height / 2 - (box.midY * zoom)
        )
        lastOffset = offset
    }

    /// 居中聚焦到指定节点并高亮
    func focusOnNode(nodeId: Int, viewSize: CGSize) {
        guard let node = workflow.nodeMap[nodeId] else { return }
        let center = CGPoint(x: node.position.x + node.nodeSize.width / 2,
                             y: node.position.y + node.nodeSize.height / 2)
        offset = CGPoint(
            x: viewSize.width / 2 - center.x * zoom,
            y: viewSize.height / 2 - center.y * zoom
        )
        lastOffset = offset
        highlightedNodeId = nodeId
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if highlightedNodeId == nodeId { highlightedNodeId = nil }
        }
    }

    /// 切换开关控件的值
    func toggleWidget(nodeId: Int, index: Int) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        var node = workflow.nodes[nodeIndex]
        guard var widgets = node.widgetsValues, index < widgets.count else { return }
        let widget = widgets[index]
        if case .toggle = widget.widgetKind {
            widgets[index] = .bool(!widget.boolValue)
            node.widgetsValues = widgets
            workflow.nodes[nodeIndex] = node
        }
    }
}
