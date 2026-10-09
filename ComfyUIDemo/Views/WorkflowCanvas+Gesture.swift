import SwiftUI

// MARK: - 手势处理（拖动手势统一入口）

extension WorkflowCanvasView {

    /// 拖动手势进行中：区分"点击 / 拖动"，并驱动节点拖动、连线、滑块、画布平移
    func handleDragChanged(_ value: DragGesture.Value) {
        // 首次触发时记录起点，重置移动标记
        if gestureStartLocation == nil {
            gestureStartLocation = value.location
            gestureDidMove = false
        }
        // 移动超过 3pt 就算真拖动
        if abs(value.translation.width) > 3 || abs(value.translation.height) > 3 {
            gestureDidMove = true
        }

        let rawStartX = value.location.x - value.translation.width
        let rawStartY = value.location.y - value.translation.height
        let startWorldX = (rawStartX - offset.x) / zoom
        let startWorldY = (rawStartY - offset.y) / zoom
        let startPoint = CGPoint(x: startWorldX, y: startWorldY)

        let currentWorldX = (value.location.x - offset.x) / zoom
        let currentWorldY = (value.location.y - offset.y) / zoom
        let currentPoint = CGPoint(x: currentWorldX, y: currentWorldY)

        // 正在连线时，更新预览线终点并检测吸附
        if isConnecting {
            connectingTo = currentPoint
            snappedInputSlot = findNearestInputSlot(point: currentPoint, maxDistance: 40)
            return
        }

        // 正在拖动节点时，更新节点位置
        if let nodeId = draggingNodeId,
           let startPos = dragStartNodePos,
           let startTouch = dragStartTouchPos {
            let deltaX = currentPoint.x - startTouch.x
            let deltaY = currentPoint.y - startTouch.y
            moveNode(id: nodeId, to: CGPoint(x: startPos.x + deltaX, y: startPos.y + deltaY))
            return
        }

        // 只有真正移动过才进入"开始连线 / 滑块 / 拖动节点 / 画布平移"分支
        // 否则纯点击会误触这些入口
        guard gestureDidMove else { return }

        // 检查是否起点在输出插槽（开始连线）
        if let outputSlot = hitTestOutputSlot(point: startPoint) {
            isConnecting = true
            connectingFrom = outputSlot
            if let node = workflow.nodeMap[outputSlot.nodeId] {
                connectingFromPoint = getSlotPosition(
                    node: node,
                    slotIndex: outputSlot.slotIndex,
                    isOutput: true
                )
            }
            connectingTo = currentPoint
            snappedInputSlot = nil
            return
        }

        // 滑块拖动（只要起点在滑块区域）
        if let slider = hitTestSlider(point: startPoint) {
            updateSliderValue(nodeId: slider.nodeId, index: slider.index, worldX: currentPoint.x)
            return
        }

        // 检查是否起点在节点的可拖动区域
        if let node = hitTestNodeDraggableArea(point: startPoint) {
            draggingNodeId = node.id
            dragStartNodePos = node.position
            dragStartTouchPos = startPoint
            return
        }

        // 起点不在节点/滑块/插槽区域 → 平移画布
        offset = CGPoint(
            x: lastOffset.x + value.translation.width,
            y: lastOffset.y + value.translation.height
        )
    }

    /// 拖动手势结束：收尾连线/节点拖动/画布平移；若未移动则视为点击
    func handleDragEnded(_ value: DragGesture.Value) {
        if isConnecting {
            let currentWorldX = (value.location.x - offset.x) / zoom
            let currentWorldY = (value.location.y - offset.y) / zoom
            let endPoint = CGPoint(x: currentWorldX, y: currentWorldY)
            if let targetSlot = snappedInputSlot ?? hitTestInputSlot(point: endPoint),
               let from = connectingFrom {
                createLink(from: from, to: targetSlot)
            }
            isConnecting = false
            connectingFrom = nil
            connectingFromPoint = nil
            connectingTo = nil
            snappedInputSlot = nil
        } else if draggingNodeId != nil {
            draggingNodeId = nil
            dragStartNodePos = nil
            dragStartTouchPos = nil
        } else {
            lastOffset = offset
        }

        // 未移动 → 视为点击，走点击处理逻辑
        if !gestureDidMove, let tapLocation = gestureStartLocation {
            handleTap(at: tapLocation)
        }

        // 重置手势状态
        gestureStartLocation = nil
        gestureDidMove = false
    }

    /// 点击处理（原 onTapGesture 的内容）
    func handleTap(at screenLocation: CGPoint) {
        let worldX = (screenLocation.x - offset.x) / zoom
        let worldY = (screenLocation.y - offset.y) / zoom
        let worldPoint = CGPoint(x: worldX, y: worldY)

        // 点击输出插槽时不做处理（连线由拖动手势处理）
        if hitTestOutputSlot(point: worldPoint) != nil {
            return
        }

        // 查找点击的节点
        var hitNode: NodeModel?
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            if rect.contains(worldPoint) {
                hitNode = node
                break
            }
        }

        guard let node = hitNode else {
            // 点击画布空白区域 → 不做处理
            return
        }

        let rect = CGRect(origin: node.position, size: node.nodeSize)
        let headerHeight = min(30, rect.height * 0.4)

        // 1. 右上角双圈圆点 → 弹出详情页（与绘制尺寸保持一致：18 + 6）
        let infoButtonSize: CGFloat = 18
        let infoButtonX = rect.maxX - infoButtonSize - 6
        let infoButtonY = rect.minY + headerHeight / 2 - infoButtonSize / 2
        let infoButtonRect = CGRect(x: infoButtonX, y: infoButtonY, width: infoButtonSize, height: infoButtonSize)
        if infoButtonRect.contains(worldPoint) {
            selectedNodeId = node.id
            return
        }

        // 2. 计算控件区域（与 drawNodes 保持一致的动态边距）
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
        let widgetX = rect.minX + leftInset
        let widgetWidth = rect.width - leftInset - rightInset
        let widgetRect = CGRect(x: widgetX, y: widgetTop, width: widgetWidth, height: widgetBottom - widgetTop)

        let isInWidgetArea = widgetRect.contains(worldPoint)
        let hasWidgets = (node.widgetsValues?.count ?? 0) > 0

        if isInWidgetArea && hasWidgets {
            let rowHeight: CGFloat = 22
            let relativeY = worldPoint.y - widgetTop
            let index = Int(relativeY / rowHeight)
            guard index >= 0, index < (node.widgetsValues?.count ?? 0) else { return }
            let widget = node.widgetsValues![index]
            if case .toggle = widget.widgetKind {
                toggleWidget(nodeId: node.id, index: index)
            } else {
                editingWidget = (node.id, index)
                editingText = widget.displayString
                showWidgetEditor = true
            }
        }
    }
}
