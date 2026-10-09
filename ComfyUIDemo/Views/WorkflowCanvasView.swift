import SwiftUI

/// 工作流画布视图：使用 SwiftUI Canvas 高性能渲染分组、连线、节点与控件
/// 支持双指缩放、单指拖拽、节点点击查看详情、重置视角
struct WorkflowCanvasView: View {
    /// 工作流数据绑定（支持弹窗修改参数后同步画布与父视图）
    @Binding var workflow: WorkflowModel
    /// 当前平移偏移
    @State private var offset: CGPoint = .zero
    /// 当前缩放比例
    @State private var zoom: CGFloat = 1.0
    /// 上一次手势结束时的平移偏移
    @State private var lastOffset: CGPoint = .zero
    /// 上一次手势结束时的缩放比例
    @State private var lastZoom: CGFloat = 1.0
    /// 当前选中的节点ID
    @State private var selectedNodeId: Int?
    /// 是否已经执行过初始适配
    @State private var hasFitted = false
    /// 当前视图尺寸
    @State private var viewSize: CGSize = .zero
    /// 高亮节点ID（搜索定位时使用）
    @State private var highlightedNodeId: Int?
    /// 当前正在编辑的单个参数（nodeId + widgetIndex）
    @State private var editingWidget: (nodeId: Int, index: Int)?
    /// 单参数编辑弹窗的输入文本
    @State private var editingText: String = ""
    /// 是否显示单参数编辑弹窗
    @State private var showWidgetEditor: Bool = false
    /// 连线状态：是否正在连线
    @State private var isConnecting: Bool = false
    /// 连线起点（源节点ID + 输出插槽索引）
    @State private var connectingFrom: (nodeId: Int, slotIndex: Int)?
    /// 连线当前终点（手指位置，世界坐标）
    @State private var connectingTo: CGPoint?
    /// 连线起点的世界坐标（用于绘制预览线）
    @State private var connectingFromPoint: CGPoint?
    /// 当前被吸附的输入插槽（用于高亮显示和自动吸附）
    @State private var snappedInputSlot: (nodeId: Int, slotIndex: Int)?
    /// 正在拖动的节点ID（节点自由移动）
    @State private var draggingNodeId: Int?
    /// 拖动开始时节点的位置（世界坐标）
    @State private var dragStartNodePos: CGPoint?
    /// 拖动开始时手指的位置（世界坐标）
    @State private var dragStartTouchPos: CGPoint?

    // MARK: - 手势区分状态（点击 vs 拖动）
    /// 本次手势是否真正移动过（用于区分点击与拖动）
    @State private var gestureDidMove: Bool = false
    /// 本次手势的起始屏幕坐标
    @State private var gestureStartLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Canvas { context, size in
                    // 记录视图尺寸
                    if viewSize != size {
                        DispatchQueue.main.async { viewSize = size }
                    }

                    // 绘制背景网格（屏幕坐标系）
                    drawGrid(context: context, viewSize: size)

                    // 画布内部矩阵变换
                    context.translateBy(x: offset.x, y: offset.y)
                    context.scaleBy(x: zoom, y: zoom)

                    // 层级1：分组背景（最底层）
                    drawGroups(context: context)

                    // 层级2：连线
                    drawLinks(context: context)

                    // 层级2.5：连线预览（正在连线时）
                    if isConnecting, let fromPoint = connectingFromPoint, let toPoint = connectingTo {
                        var actualToPoint = toPoint
                        if let snapped = snappedInputSlot,
                           let snappedNode = workflow.nodeMap[snapped.nodeId] {
                            actualToPoint = getSlotPosition(node: snappedNode, slotIndex: snapped.slotIndex, isOutput: false)
                            var highlightCircle = Path()
                            highlightCircle.addEllipse(in: CGRect(x: actualToPoint.x - 10, y: actualToPoint.y - 10, width: 20, height: 20))
                            context.fill(highlightCircle, with: .color(.green.opacity(0.5)))
                        }
                        let previewPath = bezierLinkPath(from: fromPoint, to: actualToPoint)
                        context.stroke(previewPath, with: .color(.blue.opacity(0.7)), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                        var endCircle = Path()
                        endCircle.addEllipse(in: CGRect(x: actualToPoint.x - 6, y: actualToPoint.y - 6, width: 12, height: 12))
                        context.fill(endCircle, with: .color(snappedInputSlot != nil ? .green : .blue))
                    }

                    // 层级3：节点
                    drawNodes(context: context, highlightedId: highlightedNodeId)
                }
                .gesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleDragChanged(value)
                            }
                            .onEnded { value in
                                handleDragEnded(value)
                            },
                        MagnificationGesture()
                            .onChanged { value in
                                zoom = CanvasMath.clamp(
                                    lastZoom * value,
                                    min: CanvasMath.minZoom,
                                    max: CanvasMath.maxZoom
                                )
                            }
                            .onEnded { _ in
                                lastZoom = zoom
                            }
                    )
                )
                .sheet(item: Binding(
                    get: { selectedNodeId.map { NodeIDWrapper(id: $0) } },
                    set: { selectedNodeId = $0?.id }
                )) { wrapper in
                    NodeDetailSheet(workflow: $workflow, nodeId: wrapper.id)
                }
                .alert("编辑参数", isPresented: $showWidgetEditor) {
                    TextField("参数值", text: $editingText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("取消", role: .cancel) {
                        editingWidget = nil
                    }
                    Button("保存") {
                        let target = editingWidget
                        editingWidget = nil
                        if let target = target {
                            saveEditedWidget(nodeId: target.nodeId, index: target.index, text: editingText)
                        }
                    }
                } message: {
                    if let editing = editingWidget,
                       let node = workflow.nodeMap[editing.nodeId],
                       let widgets = node.widgetsValues,
                       editing.index < widgets.count {
                        let rawName = editing.index < node.widgetNames.count ? node.widgetNames[editing.index] : "参数\(editing.index + 1)"
                        Text(SlotLocalization.bilingual(for: rawName))
                    } else {
                        Text("")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .resetCanvasView)) { _ in
                    fitToView(size: geometry.size)
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusNode)) { notification in
                    if let nodeId = notification.object as? Int {
                        focusOnNode(nodeId: nodeId, viewSize: geometry.size)
                    }
                }
                .onAppear {
                    if !hasFitted {
                        hasFitted = true
                        DispatchQueue.main.async {
                            fitToView(size: geometry.size)
                        }
                    }
                }

                // 小地图（右下角悬浮）
                MiniMapView(
                    workflow: workflow,
                    offset: offset,
                    zoom: zoom,
                    viewSize: geometry.size,
                    onTap: { worldPoint in
                        offset = CGPoint(
                            x: geometry.size.width / 2 - worldPoint.x * zoom,
                            y: geometry.size.height / 2 - worldPoint.y * zoom
                        )
                        lastOffset = offset
                    },
                    onDrag: { worldPoint in
                        offset = CGPoint(
                            x: geometry.size.width / 2 - worldPoint.x * zoom,
                            y: geometry.size.height / 2 - worldPoint.y * zoom
                        )
                        lastOffset = offset
                    }
                )
                .padding(12)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 手势处理（拖动手势统一入口）

    /// 拖动手势进行中：区分"点击 / 拖动"，并驱动节点拖动、连线、滑块、画布平移
    private func handleDragChanged(_ value: DragGesture.Value) {
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
    private func handleDragEnded(_ value: DragGesture.Value) {
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
    private func handleTap(at screenLocation: CGPoint) {
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

    // MARK: - 分组绘制

    /// 绘制分组背景框与标题（最底层，ComfyUI风格）
    private func drawGroups(context: GraphicsContext) {
        for group in workflow.groups {
            let rect = group.frame
            guard rect.width > 0, rect.height > 0 else { continue }

            let shape = RoundedRectangle(cornerRadius: 12)
            context.fill(shape.path(in: rect), with: .color(group.groupColor))
            context.stroke(shape.path(in: rect), with: .color(group.borderColor), lineWidth: 2)

            let titleBgRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: 28
            )
            context.fill(Path(titleBgRect), with: .color(group.borderColor.opacity(0.25)))

            let titleText = Text(group.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(group.borderColor)
            let titleTextRect = CGRect(
                x: rect.minX + 14,
                y: rect.minY + 4,
                width: rect.width - 28,
                height: 20
            )
            context.draw(titleText, in: titleTextRect)
        }
    }

    // MARK: - 连线绘制

    /// 绘制所有节点间的贝塞尔连线
    private func drawLinks(context: GraphicsContext) {
        for link in workflow.links {
            guard let sourceNode = workflow.nodeMap[link.sourceId],
                  let targetNode = workflow.nodeMap[link.targetId] else {
                continue
            }

            let sourcePoint = getSlotPosition(
                node: sourceNode,
                slotIndex: link.sourceSlot,
                isOutput: true
            )
            let targetPoint = getSlotPosition(
                node: targetNode,
                slotIndex: link.targetSlot,
                isOutput: false
            )

            let path = bezierLinkPath(from: sourcePoint, to: targetPoint)
            let sourceSlotType = sourceNode.outputs?[safe: link.sourceSlot]?.type
            let linkColor = SlotTypeColor.color(for: sourceSlotType ?? link.linkType)
            context.stroke(path, with: .color(linkColor), lineWidth: 2.5)
        }
    }

    /// 生成两点间的三次贝塞尔曲线路径
    private func bezierLinkPath(from: CGPoint, to: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            let dx = to.x - from.x
            let offset = min(150.0, max(30.0, abs(dx) * 0.5))
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + offset, y: from.y),
                control2: CGPoint(x: to.x - offset, y: to.y)
            )
        }
    }

    // MARK: - 节点绘制

    /// 绘制所有节点
    private func drawNodes(context: GraphicsContext, highlightedId: Int? = nil) {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            let shape = RoundedRectangle(cornerRadius: 8)

            if highlightedId == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -6, dy: -6)), with: .color(.yellow.opacity(0.4)))
            }

            if draggingNodeId == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -4, dy: -4)), with: .color(.black.opacity(0. header2)))
            }

            context.fill(shape.path(in: rect), with: .color(node.bodyColor))
            context.stroke(shape.path(in: rect), with: .colorRect(node.headerColor), line.Width: 2)

            let headerHeight = min(30, rect.height * 0.4ins)
            let headerRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: headeretHeight
            )
            context.fill(shape.path(in: headerRect), with: .color(node.headerColor))

            let titleByText = Text(node.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            context.draw(titleText, in:(dx: 8, dy: 6))

            // 右上角双圈圆点（详情页入口）——与 handleTap 的命中测试保持一致：18 + 6
            let infoButtonSize: CGFloat = 18
            let infoButtonX = rect.maxX - infoButtonSize - 6
            let infoButtonY = headerRect.midY - infoButtonSize / 2
            let infoButtonRect = CGRect(x: infoButtonX, y: infoButtonY, width: infoButtonSize, height: infoButtonSize)
            context.stroke(Path(ellipseIn: infoButtonRect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            let innerInset: CGFloat = 4
            context.stroke(Path(ellipseIn: infoButtonRect.insetBy(dx: innerInset, dy: innerInset)), with: .color(.white.opacity(0.9)), lineWidth: 1.5)

            // 控件区域
            let widgetTop = headerRect.maxY + 6
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
            let widgetWidth = max(40, rect.width - leftInset - rightInset)
            if let widgets = node.widgetsValues, !widgets.isEmpty, widgetWidth > 40 {
                drawWidgets(
                    context: context,
                    widgets: widgets,
                    names: node.widgetNames,
                    in: CGRect(x: widgetX, y: widgetTop, width: widgetWidth, height: widgetBottom - widgetTop)
                )
            }

            let typeLabelHeight: CGFloat = 16
            let typeRect = CGRect(
                x: rect.minX,
                y: rect.maxY - typeLabelHeight,
                width: rect.width,
                height: typeLabelHeight
            )
            let typeText = Text(node.type)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            context.draw(typeText, in: typeRect.insetBy(dx: 8, dy: 2))

            drawSlots(context: context, node: node)
        }
    }

    // MARK: - 控件绘制

    /// 绘制节点内部控件
    private func drawWidgets(context: GraphicsContext, widgets: [WidgetValue], names: [String], in rect: CGRect) {
        let controlHeight: CGFloat = 16
        let rowSpacing: CGFloat = 6
        let labelWidth: CGFloat = 48
        let labelFont = UIFont.systemFont(ofSize: 8)
        let valueFont = UIFont.systemFont(ofSize: 8)
        var currentY = rect.minY

        for (index, widget) in widgets.enumerated() {
            let totalRowHeight = controlHeight + rowSpacing

            let rawName = index < names.count ? names[index] : "参数\(index + 1)"
            let paramName = SlotLocalization.localized(for: rawName)
            let displayName = truncatedText(paramName, font: labelFont, maxWidth: labelWidth - 4)
            let labelText = Text(displayName)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            let labelCenterY = currentY + controlHeight / 2
            context.draw(labelText, at: CGPoint(x: rect.minX + labelWidth - 2, y: labelCenterY), anchor: .trailing)

            let controlX = rect.minX + labelWidth + 4
            let controlWidth = rect.width - labelWidth - 4
            let controlY = currentY

            switch widget.widgetKind {
            case .toggle:
                let isOn = widget.boolValue
                let toggleRect = CGRect(x: controlX, y: controlY + 1, width: 28, height: 14)
                let toggleShape = RoundedRectangle(cornerRadius: 7)
                context.fill(toggleShape.path(in: toggleRect), with: .color(isOn ? .green : .gray.opacity(0.4)))
                let knobX = isOn ? toggleRect.maxX - 11 : toggleRect.minX + 2
                let knobRect = CGRect(x: knobX, y: toggleRect.minY + 1, width: 11, height: 12)
                context.fill(Path(ellipseIn: knobRect), with: .color(.white))
                let statusText = Text(isOn ? "开" : "关")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                context.draw(statusText, at: CGPoint(x: toggleRect.maxX + 4, y: controlY + 8), anchor: .leading)

            case .number:
                let numWidth: CGFloat = 48
                let numRect = CGRect(x: controlX, y: controlY, width: numWidth, height: controlHeight)
                let numShape = RoundedRectangle(cornerRadius: 4)
                context.fill(numShape.path(in: numRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(numShape.path(in: numRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                let numText = Text(widget.displayString)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                context.draw(numText, in: numRect.insetBy(dx: 4, dy: 1))

                let sliderX = numRect.maxX + 6
                let sliderWidth = max(0, controlWidth - numWidth - 6)
                if sliderWidth > 20 {
                    let sliderRect = CGRect(x: sliderX, y: controlY + 6, width: sliderWidth, height: 4)
                    context.fill(Path(roundedRect: sliderRect, cornerSize: CGSize(width: 2, height: 2)),
                               with: .color(.gray.opacity(0.25)))
                    let numericValue: Double
                    switch widget {
                    case .int(let v): numericValue = Double(v)
                    case .double(let v): numericValue = v
                    default: numericValue = 0
                    }
                    let ratio = max(0, min(1, numericValue / 100))
                    let knobX = sliderX + sliderWidth * ratio
                    let knobRect = CGRect(x: knobX - 4, y: controlY + 3, width: 8, height: 10)
                    context.fill(Path(ellipseIn: knobRect), with: .color(.blue))
                }

            case .text:
                let text = widget.displayString
                let isShortEnum = text.count <= 15 && !text.contains(" ") && !text.contains("\n") && controlWidth > 60
                let textRect = CGRect(x: controlX, y: controlY, width: controlWidth, height: controlHeight)
                let textShape = RoundedRectangle(cornerRadius: 4)
                context.fill(textShape.path(in: textRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(textShape.path(in: textRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)

                let textMaxWidth = isShortEnum ? controlWidth - 16 : controlWidth - 8
                let displayText = truncatedText(text, font: valueFont, maxWidth: textMaxWidth)
                let textView = Text(displayText)
                    .font(.system(size: 8))
                    .foregroundColor(.primary)
                context.draw(textView, in: textRect.insetBy(dx: 4, dy: 2))

                if isShortEnum {
                    let arrowX = textRect.maxX - 12
                    let arrowPath = Path { p in
                        p.move(to: CGPoint(x: arrowX, y: controlY + 5))
                        p.addLine(to: CGPoint(x: arrowX + 4, y: controlY + 9))
                        p.addLine(to: CGPoint(x: arrowX + 8, y: controlY + 5))
                    }
                    context.stroke(arrowPath, with: .color(.gray), lineWidth: 1)
                }
            }

            currentY += totalRowHeight
        }
    }

    // MARK: - 插槽绘制与定位

    /// 绘制节点的输入/输出插槽及名称标签
    private func drawSlots(context: GraphicsContext, node: NodeModel) {
        let dotSize: CGFloat = 10
        let labelFont = UIFont.systemFont(ofSize: 9)

        if let outputs = node.outputs {
            for (index, slot) in outputs.enumerated() {
                let point = getSlotPosition(node: node, slotIndex: index, isOutput: true)
                let dotRect = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let slotColor = SlotTypeColor.color(for: slot.type)
                context.fill(Path(ellipseIn: dotRect), with: .color(slotColor))
                context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)

                if let slotName = slot.name, !slotName.isEmpty {
                    let localized = SlotLocalization.localized(for: slotName)
                    let maxWidth: CGFloat = 70
                    let displayName = truncatedText(localized, font: labelFont, maxWidth: maxWidth)
                    let nameText = Text(displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    let labelPoint = CGPoint(x: point.x - dotSize / 2 - 5, y: point.y)
                    context.draw(nameText, at: labelPoint, anchor: .trailing)
                }
            }
        }

        if let inputs = node.inputs {
            for (index, slot) in inputs.enumerated() {
                let point = getSlotPosition(node: node, slotIndex: index, isOutput: false)
                let dotRect = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let slotColor = SlotTypeColor.color(for: slot.type)
                context.fill(Path(ellipseIn: dotRect), with: .color(slotColor))
                context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)

                if let slotName = slot.name, !slotName.isEmpty {
                    let localized = SlotLocalization.localized(for: slotName)
                    let maxWidth: CGFloat = 60
                    let displayName = truncatedText(localized, font: labelFont, maxWidth: maxWidth)
                    let nameText = Text(displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    let labelPoint = CGPoint(x: point.x + dotSize / 2 + 5, y: point.y)
                    context.draw(nameText, at: labelPoint, anchor: .leading)
                }
            }
        }
    }

    /// 文本截断
    private func truncatedText(_ text: String, font: UIFont, maxWidth: CGFloat) -> String {
        let nsText = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = nsText.size(withAttributes: attributes).width
        if textWidth <= maxWidth { return text }
        var result = text
        while result.count > 1 {
            result = String(result.dropLast())
            let candidate = result + "…"
            let candidateWidth = (candidate as NSString).size(withAttributes: attributes).width
            if candidateWidth <= maxWidth { return candidate }
        }
        return "…"
    }

    /// 计算插槽在画布中的坐标
    private func getSlotPosition(node: NodeModel, slotIndex: Int, isOutput: Bool) -> CGPoint {
        let rect = CGRect(origin: node.position, size: node.nodeSize)
        let headerHeight = min(30, rect.height * 0.4)
        let slotAreaTop = rect.minY + headerHeight + 8
        let slotGap: CGFloat = 20
        let y = slotAreaTop + CGFloat(slotIndex) * slotGap

        if isOutput {
            return CGPoint(x: rect.maxX, y: y)
        } else {
            return CGPoint(x: rect.minX, y: y)
        }
    }

    // MARK: - 背景网格

    private func drawGrid(context: GraphicsContext, viewSize: CGSize) {
        let gridStep: CGFloat = 40
        var path = Path()
        for x in stride(from: 0, through: viewSize.width, by: gridStep) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: viewSize.height))
        }
        for y in stride(from: 0, through: viewSize.height, by: gridStep) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: viewSize.width, y: y))
        }
        context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
    }

    // MARK: - 视角适配

    private func fitToView(size: CGSize) {
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
        var maxY =
 -CGFloat.greatestFiniteMagnitude
        for box in allBoxes {
            minX = min(minX, box.minX)
            minY = min               (minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box guard.maxY)
        }
        let box = CGRect(x: minX, y: minY, width: maxX - slider minX, height: maxY - minY)

        guard box.width > 0, box.height > 0 else {
           Width zoom = 1.0; offset = .zero; lastZoom = 1.0; lastOffset = .zero
            return
 >        }

        zoom = CanvasMath.computeFitScale(box: box, viewSize: size)
        lastZoom =  zoom
        offset = CGPoint(
            x: size.width / 2 - (box.midX * zoom),
            y: size.height / 2 - (box.midY * zoom)
        )
        lastOffset = offset
    }

    /// 居中聚焦到指定节点并高亮
    private func focusOnNode(nodeId: Int, viewSize: CGSize) {
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
    private func toggleWidget(nodeId: Int, index: Int) {
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

    // MARK: - 节点拖动

    /// 命中测试：判断点击位置是否在节点的可拖动区域
    private func hitTestNodeDraggableArea(point: CGPoint) -> NodeModel? {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            guard rect.contains(point) else { continue }

            let headerHeight = min(30, rect.height * 0.4)

            // 排除右上角详情按钮区域（与绘制尺寸保持一致：18 + 6）
            let infoButtonSize: CGFloat = 18
            let infoButtonX = rect.maxX - infoButtonSize - 6
            let infoButtonY = rect.minY + headerHeight / 2 - infoButtonSize / 2
            let infoButtonRect = CGRect(x: infoButtonX, y: infoButtonY, width: infoButtonSize, height: infoButtonSize)
            if infoButtonRect.contains(point) { continue }

            // 排除输出插槽区域（右侧边缘）
            if hitTestOutputSlot(point: point) != nil { continue }

            return node
        }
        return nil
    }

    /// 移动节点到指定位置（世界坐标）
    private func moveNode(id: Int, to position: CGPoint) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == id }) else { return }
        var node = workflow.nodes[nodeIndex]
        node.pos = [Double(position.x), Double(position.y)]
        workflow.nodes[nodeIndex] = node
    }

    /// 命中测试：判断点击位置是否在滑块区域
    private func hitTestSlider(point: CGPoint) -> (nodeId: Int, index: Int)? {
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
                let sliderWidth = widgetWidth - labelWidth - 4 - numWidth - 620 else { continue }
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
    private func hitTestOutputSlot(point: CGPoint) -> (nodeId: Int, slotIndex: Int)? {
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
    private func hitTestInputSlot(point: CGPoint) -> (nodeId: Int, slotIndex: Int)? {
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
    private func findNearestInputSlot(point: CGPoint, maxDistance: CGFloat) -> (nodeId: Int, slotIndex: Int)? {
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
    private func createLink(from: (nodeId: Int, slotIndex: Int), to: (nodeId: Int, slotIndex: Int)) {
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
    private func updateSliderValue(nodeId: Int, index: Int, worldX: CGFloat) {
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
        // 抑制未使用变量警告（widgetTop 保留以便未来扩展，实际用不到可删）
        _ = widgetTop
    }

    /// 保存单参数编辑结果
    private func saveEditedWidget(nodeId: Int, index: Int, text: String) {
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

// MARK: - 数组安全下标

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// 节点ID包装器，用于sheet(item:)
private struct NodeIDWrapper: Identifiable {
    let id: Int
}
