import SwiftUI
import CoreGraphics

/// 工作流视图模型：管理画布状态、节点操作和业务逻辑
/// 遵循MVVM架构，View层只负责渲染和转发手势事件
final class WorkflowViewModel: ObservableObject {
    // MARK: - 发布状态

    /// 工作流数据（单一数据源）
    @Published var workflow: WorkflowModel
    /// 视口状态（缩放/偏移）
    @Published var viewport = ViewportState()
    /// 当前选中用于编辑的节点ID
    @Published var selectedNodeID: Int?
    /// 高亮节点ID（搜索定位时使用）
    @Published var highlightedNodeID: Int?

    // MARK: - 初始化

    init(workflow: WorkflowModel) {
        self.workflow = workflow
    }

    // MARK: - 视口操作

    /// 自适应缩放到包含所有节点和分组
    func fitToView(size: CGSize) {
        var allBoxes: [CGRect] = workflow.nodes.map {
            CGRect(origin: $0.position, size: $0.nodeSize)
        }
        allBoxes.append(contentsOf: workflow.groups.map { $0.frame })

        guard !allBoxes.isEmpty else {
            viewport = ViewportState()
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
            viewport = ViewportState()
            return
        }

        let scale = CanvasMath.computeFitScale(box: box, viewSize: size)
        let offset = CGPoint(
            x: size.width / 2 - (box.midX * scale),
            y: size.height / 2 - (box.midY * scale)
        )
        viewport = ViewportState(scale: scale, offset: offset, lastScale: scale, lastOffset: offset)
    }

    /// 居中聚焦到指定节点并高亮
    func focusOnNode(_ nodeID: Int, viewSize: CGSize) {
        guard let node = workflow.nodeMap[nodeID] else { return }
        let center = CGPoint(
            x: node.position.x + node.nodeSize.width / 2,
            y: node.position.y + node.nodeSize.height / 2
        )
        let offset = CGPoint(
            x: viewSize.width / 2 - center.x * viewport.scale,
            y: viewSize.height / 2 - center.y * viewport.scale
        )
        viewport.offset = offset
        viewport.lastOffset = offset
        highlightedNodeID = nodeID
        // 3秒后取消高亮
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.highlightedNodeID == nodeID {
                self?.highlightedNodeID = nil
            }
        }
    }

    /// 应用平移（屏幕坐标系位移）
    func applyPan(translation: CGSize) {
        viewport.applyPan(translation: translation)
    }

    /// 应用缩放（手势倍率）
    func applyZoom(magnification: CGFloat) {
        viewport.applyZoom(
            magnification: magnification,
            minScale: CanvasMath.minZoom,
            maxScale: CanvasMath.maxZoom
        )
    }

    /// 手势结束时保存视口状态
    func saveViewportState() {
        viewport.saveState()
    }

    // MARK: - 节点操作

    /// 选中/取消选中节点
    func selectNode(_ nodeID: Int?) {
        selectedNodeID = nodeID
    }

    /// 移动节点（屏幕坐标系位移，自动转换为世界坐标）
    func moveNode(id: Int, by screenDelta: CGSize) {
        guard let index = workflow.nodes.firstIndex(where: { $0.id == id }) else { return }
        let worldDelta = CGSize(
            width: screenDelta.width / viewport.scale,
            height: screenDelta.height / viewport.scale
        )
        // position是计算属性，需要修改底层pos数组
        if workflow.nodes[index].pos.count >= 2 {
            workflow.nodes[index].pos[0] += worldDelta.width
            workflow.nodes[index].pos[1] += worldDelta.height
        }
    }

    /// 更新控件值（直接修改workflow，确保触发视图更新）
    func updateWidget(nodeID: Int, index: Int, value: WidgetValue) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeID }),
              workflow.nodes[nodeIndex].widgetsValues != nil,
              index < workflow.nodes[nodeIndex].widgetsValues!.count else { return }
        workflow.nodes[nodeIndex].widgetsValues![index] = value
    }

    /// 获取当前最新的控件值（避免使用传入的widget副本导致显示旧值）
    func currentWidgetValue(nodeID: Int, index: Int) -> WidgetValue? {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeID }),
              let widgets = workflow.nodes[nodeIndex].widgetsValues,
              index < widgets.count else { return nil }
        return widgets[index]
    }

    /// 切换开关控件
    func toggleWidget(nodeID: Int, index: Int) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeID }),
              workflow.nodes[nodeIndex].widgetsValues != nil,
              index < workflow.nodes[nodeIndex].widgetsValues!.count else { return }
        let widget = workflow.nodes[nodeIndex].widgetsValues![index]
        if case .toggle = widget.widgetKind {
            workflow.nodes[nodeIndex].widgetsValues![index] = .bool(!widget.boolValue)
        }
    }

    // MARK: - 查询

    /// 获取指定世界坐标下的节点
    func nodeAt(_ worldPoint: CGPoint) -> NodeModel? {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            if rect.contains(worldPoint) {
                return node
            }
        }
        return nil
    }

    /// 命中测试：判断世界坐标是否在滑块区域
    func hitTestSlider(worldPoint: CGPoint) -> (nodeID: Int, index: Int)? {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            let headerHeight = min(30, rect.height * 0.4)
            let widgetTop = rect.minY + headerHeight + 6
            // 与drawNodes一致的动态边距计算
            let baseLeftInset: CGFloat = 75
            let baseRightInset: CGFloat = 85
            let minWidgetWidth: CGFloat = 60
            var leftInset = baseLeftInset
            var rightInset = baseRightInset
            if rect.width - leftInset - rightInset < minWidgetWidth {
                let available = rect.width - minWidgetWidth
                let totalInset = baseLeftInset + baseRightInset
                let scale = min(1.0, available / totalInset)
                leftInset = baseLeftInset * scale
                rightInset = baseRightInset * scale
            }
            let widgetX = rect.minX + leftInset
            let widgetWidth = rect.width - leftInset - rightInset
            let labelWidth: CGFloat = 48
            let numWidth: CGFloat = 48
            let rowHeight: CGFloat = 22

            guard let widgets = node.widgetsValues else { continue }
            for (index, widget) in widgets.enumerated() {
                guard case .number = widget.widgetKind else { continue }
                let controlY = widgetTop + CGFloat(index) * rowHeight
                let sliderX = widgetX + labelWidth + 4 + numWidth + 6
                let sliderWidth = widgetWidth - labelWidth - 4 - numWidth - 6
                guard sliderWidth > 20 else { continue }
                // 扩大点击区域
                let hitRect = CGRect(x: sliderX - 6, y: controlY, width: sliderWidth + 12, height: 16)
                if hitRect.contains(worldPoint) {
                    return (node.id, index)
                }
            }
        }
        return nil
    }

    /// 根据世界坐标X更新滑块数值
    func updateSliderValue(nodeID: Int, index: Int, worldX: CGFloat) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeID }),
              workflow.nodes[nodeIndex].widgetsValues != nil,
              index < workflow.nodes[nodeIndex].widgetsValues!.count else { return }
        let node = workflow.nodes[nodeIndex]
        let rect = CGRect(origin: node.position, size: node.nodeSize)
        let headerHeight = min(30, rect.height * 0.4)
        let widgetTop = rect.minY + headerHeight + 6
        let baseLeftInset: CGFloat = 75
        let baseRightInset: CGFloat = 85
        let minWidgetWidth: CGFloat = 60
        var leftInset = baseLeftInset
        var rightInset = baseRightInset
        if rect.width - leftInset - rightInset < minWidgetWidth {
            let available = rect.width - minWidgetWidth
            let totalInset = baseLeftInset + baseRightInset
            let scale = min(1.0, available / totalInset)
            leftInset = baseLeftInset * scale
            rightInset = baseRightInset * scale
        }
        let widgetX = rect.minX + leftInset
        let widgetWidth = rect.width - leftInset - rightInset
        let labelWidth: CGFloat = 48
        let numWidth: CGFloat = 48
        let sliderX = widgetX + labelWidth + 4 + numWidth + 6
        let sliderWidth = widgetWidth - labelWidth - 4 - numWidth - 6
        guard sliderWidth > 0 else { return }

        var ratio = (worldX - sliderX) / sliderWidth
        ratio = max(0, min(1, ratio))
        let newValue = Double(round(ratio * 1000) / 10)

        let original = workflow.nodes[nodeIndex].widgetsValues![index]
        switch original {
        case .int:
            workflow.nodes[nodeIndex].widgetsValues![index] = .int(Int(newValue))
        case .double:
            workflow.nodes[nodeIndex].widgetsValues![index] = .double(newValue)
        default:
            workflow.nodes[nodeIndex].widgetsValues![index] = .double(newValue)
        }
    }

    /// 获取节点的控件区域（用于点击判断）
    func widgetArea(for node: NodeModel) -> CGRect {
        let rect = CGRect(origin: node.position, size: node.nodeSize)
        let headerHeight = min(30, rect.height * 0.4)
        let widgetTop = rect.minY + headerHeight + 6
        let widgetBottom = rect.maxY - 20
        let baseLeftInset: CGFloat = 75
        let baseRightInset: CGFloat = 85
        let minWidgetWidth: CGFloat = 60
        var leftInset = baseLeftInset
        var rightInset = baseRightInset
        if rect.width - leftInset - rightInset < minWidgetWidth {
            let available = rect.width - minWidgetWidth
            let totalInset = baseLeftInset + baseRightInset
            let scale = min(1.0, available / totalInset)
            leftInset = baseLeftInset * scale
            rightInset = baseRightInset * scale
        }
        return CGRect(
            x: rect.minX + leftInset,
            y: widgetTop,
            width: rect.width - leftInset - rightInset,
            height: widgetBottom - widgetTop
        )
    }
}
