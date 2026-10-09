import SwiftUI

// MARK: - 交互与命中测试模块

extension WorkflowCanvasView {

    // MARK: - 节点拖动

    /// 命中测试：判断点击位置是否在节点标题栏（仅标题栏可拖动节点）
    /// 手指碰到标题栏任意位置即可触发节点拖动，不再排除详情按钮/输出插槽
    func hitTestNodeDraggableArea(point: CGPoint) -> NodeModel? {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            let headerHeight = min(30, rect.height * 0.4)
            let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
            if headerRect.contains(point) {
                return node
            }
        }
        return nil
    }

    /// 移动节点到指定位置（世界坐标）
    func moveNode(id: Int, to position: CGPoint) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == id }) else { return }
        var node = workflow.nodes[nodeIndex]
        node.pos = [Double(position.x), Double(position.y)]
        workflow.nodes[nodeIndex] = node
    }

    /// 命中测试：判断点击位置是否在滑块区域
    func hitTestSlider(point: CGPoint) -> (nodeId: Int, index: Int)? {
        for node in workflow.nodes {
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
            let rowHeight: CGFloat = 22

            guard let widgets = node.widgetsValues else { continue }
            for (index, widget) in widgets.enumerated() {
                guard case .number = widget.widgetKind else { continue }
                let controlY = widgetTop + CGFloat(index) * rowHeight
                let sliderX = widgetX + labelWidth + 4 + numWidth + 6
                let sliderWidth = widgetWidth - labelWidth - 4 - numWidth - 6
                guard sliderWidth > 20 else { continue }
                let hitRect = CGRect(x: sliderX - 6, y: controlY, width: sliderWidth + 12, height: 22)
                if hitRect.contains(point) {
                    return (node.id, index)
                }
            }
        }
        return nil
    }

    // MARK: - 插槽命中测试

    /// 命中测试：判断点击位置是否在输出插槽上
    func hitTestOutputSlot(point: CGPoint) -> (nodeId: Int, slotIndex: Int)? {
        let hitRadius: CGFloat = 12
        for node in workflow.nodes {
            guard let outputs = node.outputs, !outputs.isEmpty else { continue }
            for (index, _) in outputs.enumerated() {
                let slotPos = getSlotPosition(node: node, slotIndex: index, isOutput: true)
                let distance = hypot(point.x - slotPos.x, point.y - slotPos.y)
                if distance <= hitRadius {
                    return (node.id, index)
                }
            }
        }
        return nil
    }

    /// 命中测试：判断点击位置是否在输入插槽上
    func hitTestInputSlot(point: CGPoint) -> (nodeId: Int, slotIndex: Int)? {
        let hitRadius: CGFloat = 20
        for node in workflow.nodes {
            guard let inputs = node.inputs, !inputs.isEmpty else { continue }
            for (index, _) in inputs.enumerated() {
                let slotPos = getSlotPosition(node: node, slotIndex: index, isOutput: false)
                let distance = hypot(point.x - slotPos.x, point.y - slotPos.y)
                if distance <= hitRadius {
                    return (node.id, index)
                }
            }
        }
        return nil
    }

    /// 查找最近的输入插槽（用于连线自动吸附）
    func findNearestInputSlot(point: CGPoint, maxDistance: CGFloat) -> (nodeId: Int, slotIndex: Int)? {
        var nearest: (nodeId: Int, slotIndex: Int)?
        var nearestDistance = maxDistance
        for node in workflow.nodes {
            guard let inputs = node.inputs, !inputs.isEmpty else { continue }
            for (index, _) in inputs.enumerated() {
                let slotPos = getSlotPosition(node: node, slotIndex: index, isOutput: false)
                let distance = hypot(point.x - slotPos.x, point.y - slotPos.y)
                if distance < nearestDistance {
                    nearestDistance = distance
                    nearest = (node.id, index)
                }
            }
        }
        return nearest
    }

    // MARK: - 创建连线

    /// 创建连线：从源节点输出插槽到目标节点输入插槽
    func createLink(from: (nodeId: Int, slotIndex: Int), to: (nodeId: Int, slotIndex: Int)) {
        guard from.nodeId != to.nodeId else { return }

        let newLinkId = (workflow.links.map { $0.id }.max() ?? 0) + 1
        let sourceType = workflow.nodeMap[from.nodeId]?.outputs?[safe: from.slotIndex]?.type

        let newLink = LinkModel(
            id: newLinkId,
            sourceId: from.nodeId,
            sourceSlot: from.slotIndex,
            targetId: to.nodeId,
            targetSlot: to.slotIndex,
            linkType: sourceType
        )

        workflow.links.append(newLink)
    }

    /// 根据世界坐标X更新滑块数值（范围0-100）
    func updateSliderValue(nodeId: Int, index: Int, worldX: CGFloat) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        var node = workflow.nodes[nodeIndex]
        guard var widgets = node.widgetsValues, index < widgets.count else { return }
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

        let original = widgets[index]
        switch original {
        case .int:
            widgets[index] = .int(Int(newValue))
        case .double:
            widgets[index] = .double(newValue)
        default:
            widgets[index] = .double(newValue)
        }
        node.widgetsValues = widgets
        workflow.nodes[nodeIndex] = node
        // 抑制未使用变量警告（widgetTop 保留以便未来扩展）
        _ = widgetTop
    }

    /// 保存单参数编辑结果
    func saveEditedWidget(nodeId: Int, index: Int, text: String) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        var node = workflow.nodes[nodeIndex]
        guard var widgets = node.widgetsValues, index < widgets.count else { return }
        let original = widgets[index]
        switch original {
        case .int:
            if let intValue = Int(text) {
                widgets[index] = .int(intValue)
            } else if let doubleValue = Double(text) {
                widgets[index] = .double(doubleValue)
            } else {
                widgets[index] = .string(text)
            }
        case .double:
            if let doubleValue = Double(text) {
                widgets[index] = .double(doubleValue)
            } else {
                widgets[index] = .string(text)
            }
        case .string:
            widgets[index] = .string(text)
        case .bool:
            widgets[index] = .bool(text.lowercased() == "true" || text == "1" || text.lowercased() == "开")
        case .null:
            widgets[index] = .string(text)
        }
        node.widgetsValues = widgets
        workflow.nodes[nodeIndex] = node
    }
}
