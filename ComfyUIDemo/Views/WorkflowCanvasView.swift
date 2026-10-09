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
    /// 当前选中用于编辑的节点ID（点击节点空白区域选中，点击画布空白区域取消）
    @State private var selectedNodeIdForEdit: Int?
    /// 连线状态：是否正在连线
    @State private var isConnecting: Bool = false
    /// 连线起点（源节点ID + 输出插槽索引）
    @State private var connectingFrom: (nodeId: Int, slotIndex: Int)?
    /// 连线当前终点（手指位置，世界坐标）
    @State private var connectingTo: CGPoint?
    /// 连线起点的世界坐标（用于绘制预览线）
    @State private var connectingFromPoint: CGPoint?

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
                        let previewPath = bezierLinkPath(from: fromPoint, to: toPoint)
                        context.stroke(previewPath, with: .color(.blue.opacity(0.7)), lineWidth: 3, style: StrokeStyle(lineDash: [8, 4]))
                        // 绘制终点圆点
                        var endCircle = Path()
                        endCircle.addEllipse(in: CGRect(x: toPoint.x - 6, y: toPoint.y - 6, width: 12, height: 12))
                        context.fill(endCircle, with: .color(.blue))
                    }

                    // 层级3：节点
                    drawNodes(context: context, highlightedId: highlightedNodeId)
                }
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                // 正在连线时，更新预览线终点
                                if isConnecting {
                                    let worldX = (value.location.x - offset.x) / zoom
                                    let worldY = (value.location.y - offset.y) / zoom
                                    connectingTo = CGPoint(x: worldX, y: worldY)
                                    return
                                }

                                let startWorldX = (value.startLocation.x - offset.x) / zoom
                                let startWorldY = (value.startLocation.y - offset.y) / zoom
                                let startPoint = CGPoint(x: startWorldX, y: startWorldY)

                                // 检查是否点击了输出插槽（开始连线，无需选中节点）
                                if let outputSlot = hitTestOutputSlot(point: startPoint) {
                                    isConnecting = true
                                    connectingFrom = outputSlot
                                    connectingFromPoint = getSlotPosition(
                                        node: workflow.nodeMap[outputSlot.nodeId]!,
                                        slotIndex: outputSlot.slotIndex,
                                        isOutput: true
                                    )
                                    connectingTo = startPoint
                                    return
                                }

                                // 只有当节点被选中时，才允许滑块拖动编辑
                                if selectedNodeIdForEdit != nil {
                                    if let slider = hitTestSlider(point: startPoint),
                                       slider.nodeId == selectedNodeIdForEdit {
                                        // 选中节点的滑块拖动 → 更新参数
                                        let currentWorldX = (value.location.x - offset.x) / zoom
                                        updateSliderValue(nodeId: slider.nodeId, index: slider.index, worldX: currentWorldX)
                                        return
                                    }
                                }
                                // 未选中节点或起点不在滑块区域 → 平移画布
                                offset = CGPoint(
                                    x: lastOffset.x + value.translation.width,
                                    y: lastOffset.y + value.translation.height
                                )
                            }
                            .onEnded { value in
                                // 正在连线时，检查终点是否在输入插槽上
                                if isConnecting {
                                    let worldX = (value.location.x - offset.x) / zoom
                                    let worldY = (value.location.y - offset.y) / zoom
                                    let endPoint = CGPoint(x: worldX, y: worldY)

                                    if let inputSlot = hitTestInputSlot(point: endPoint),
                                       let from = connectingFrom {
                                        // 创建连线
                                        createLink(from: from, to: inputSlot)
                                    }

                                    // 重置连线状态
                                    isConnecting = false
                                    connectingFrom = nil
                                    connectingFromPoint = nil
                                    connectingTo = nil
                                    return
                                }

                                lastOffset = offset
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
                .onTapGesture { location in
                    let worldX = (location.x - offset.x) / zoom
                    let worldY = (location.y - offset.y) / zoom
                    let worldPoint = CGPoint(x: worldX, y: worldY)

                    // 点击输出插槽时不做处理（连线由DragGesture处理）
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
                        // 点击画布空白区域 → 取消选中状态
                        selectedNodeIdForEdit = nil
                        return
                    }

                    let rect = CGRect(origin: node.position, size: node.nodeSize)
                    let headerHeight = min(30, rect.height * 0.4)

                    // 1. 右上角双圈圆点 → 弹出详情页（不受选中状态限制）
                    let infoButtonSize: CGFloat = 24
                    let infoButtonX = rect.maxX - infoButtonSize - 3
                    let infoButtonY = rect.minY + headerHeight / 2 - infoButtonSize / 2
                    let infoButtonRect = CGRect(x: infoButtonX, y: infoButtonY, width: infoButtonSize, height: infoButtonSize)
                    if infoButtonRect.contains(worldPoint) {
                        selectedNodeId = node.id
                        return
                    }

                    // 2. 计算控件区域（与drawNodes一致的动态边距）
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
                        // 点击控件区域
                        if selectedNodeIdForEdit == node.id {
                            // 节点已选中 → 编辑参数
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
                        } else {
                            // 节点未选中 → 先选中节点
                            selectedNodeIdForEdit = node.id
                        }
                    } else {
                        // 点击节点空白区域（header或控件区外）→ 选中节点
                        selectedNodeIdForEdit = node.id
                    }
                }
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
                        // 先获取editingWidget，再清空，避免alert关闭时editingWidget被置nil
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
                        // 点击小地图跳转：使点击点居中
                        offset = CGPoint(
                            x: geometry.size.width / 2 - worldPoint.x * zoom,
                            y: geometry.size.height / 2 - worldPoint.y * zoom
                        )
                        lastOffset = offset
                    },
                    onDrag: { worldPoint in
                        // 拖拽小地图实时平移
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

    // MARK: - 分组绘制

    /// 绘制分组背景框与标题（最底层，ComfyUI风格）
    private func drawGroups(context: GraphicsContext) {
        for group in workflow.groups {
            let rect = group.frame
            guard rect.width > 0, rect.height > 0 else { continue }

            let shape = RoundedRectangle(cornerRadius: 12)
            // 分组半透明背景
            context.fill(shape.path(in: rect), with: .color(group.groupColor))
            // 分组边框
            context.stroke(shape.path(in: rect), with: .color(group.borderColor), lineWidth: 2)

            // 分组标题背景条（顶部矩形）
            let titleBgRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: 28
            )
            context.fill(Path(titleBgRect), with: .color(group.borderColor.opacity(0.25)))

            // 分组标题文字
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

    /// 生成两点间的三次贝塞尔曲线路径（动态控制点，基于水平距离，避免绕大圈）
    private func bezierLinkPath(from: CGPoint, to: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            let dx = to.x - from.x
            // 动态偏移：基于水平距离，下限30，上限150
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

            // 高亮节点发光效果（搜索定位）
            if highlightedId == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -6, dy: -6)), with: .color(.yellow.opacity(0.4)))
            }

            // 选中编辑状态：蓝色发光边框
            if selectedNodeIdForEdit == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -4, dy: -4)), with: .color(.blue.opacity(0.3)))
                context.stroke(shape.path(in: rect.insetBy(dx: -2, dy: -2)), with: .color(.blue), lineWidth: 2.5)
            }

            context.fill(shape.path(in: rect), with: .color(node.bodyColor))
            context.stroke(shape.path(in: rect), with: .color(node.headerColor), lineWidth: 2)

            let headerHeight = min(30, rect.height * 0.4)
            let headerRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: headerHeight
            )
            context.fill(shape.path(in: headerRect), with: .color(node.headerColor))

            let titleText = Text(node.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            context.draw(titleText, in: headerRect.insetBy(dx: 8, dy: 6))

            // 右上角双圈圆点（详情页入口）
            let infoButtonSize: CGFloat = 18
            let infoButtonX = rect.maxX - infoButtonSize - 6
            let infoButtonY = headerRect.midY - infoButtonSize / 2
            let infoButtonRect = CGRect(x: infoButtonX, y: infoButtonY, width: infoButtonSize, height: infoButtonSize)
            // 外圈
            context.stroke(Path(ellipseIn: infoButtonRect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            // 内圈
            let innerInset: CGFloat = 4
            context.stroke(Path(ellipseIn: infoButtonRect.insetBy(dx: innerInset, dy: innerInset)), with: .color(.white.opacity(0.9)), lineWidth: 1.5)

            // 控件区域（居中，避开左右两侧插槽标签区域）
            // 边距根据节点宽度动态调整，确保窄节点也有控件显示空间
            let widgetTop = headerRect.maxY + 6
            let widgetBottom = rect.maxY - 20
            // 基础边距：左侧输入插槽标签+圆点，右侧输出插槽标签+圆点
            let baseLeftInset: CGFloat = 75
            let baseRightInset: CGFloat = 85
            // 节点较窄时按比例压缩边距，确保控件区域最小宽度60pt
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

            // 节点类型文字（底部）
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

    /// 绘制节点内部控件（只读展示，参数名与控件同一行显示，文本单行截断，全部展示不折叠）
    private func drawWidgets(context: GraphicsContext, widgets: [WidgetValue], names: [String], in rect: CGRect) {
        let controlHeight: CGFloat = 16
        let rowSpacing: CGFloat = 6
        let labelWidth: CGFloat = 48
        let labelFont = UIFont.systemFont(ofSize: 8)
        let valueFont = UIFont.systemFont(ofSize: 8)
        var currentY = rect.minY

        for (index, widget) in widgets.enumerated() {
            // 固定行高，文本单行显示不换行
            let totalRowHeight = controlHeight + rowSpacing

            // 参数名标签（左侧，固定宽度，右对齐，与控件垂直居中）
            let rawName = index < names.count ? names[index] : "参数\(index + 1)"
            let paramName = SlotLocalization.localized(for: rawName)
            let displayName = truncatedText(paramName, font: labelFont, maxWidth: labelWidth - 4)
            let labelText = Text(displayName)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            let labelCenterY = currentY + controlHeight / 2
            context.draw(labelText, at: CGPoint(x: rect.minX + labelWidth - 2, y: labelCenterY), anchor: .trailing)

            // 控件区域（右侧，剩余宽度）
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
                // 数字框 + 迷你滑块条
                let numWidth: CGFloat = 48
                let numRect = CGRect(x: controlX, y: controlY, width: numWidth, height: controlHeight)
                let numShape = RoundedRectangle(cornerRadius: 4)
                context.fill(numShape.path(in: numRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(numShape.path(in: numRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                let numText = Text(widget.displayString)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                context.draw(numText, in: numRect.insetBy(dx: 4, dy: 1))

                // 迷你滑块条（可拖动交互，旋钮位置根据数值比例显示）
                let sliderX = numRect.maxX + 6
                let sliderWidth = max(0, controlWidth - numWidth - 6)
                if sliderWidth > 20 {
                    let sliderRect = CGRect(x: sliderX, y: controlY + 6, width: sliderWidth, height: 4)
                    context.fill(Path(roundedRect: sliderRect, cornerSize: CGSize(width: 2, height: 2)),
                               with: .color(.gray.opacity(0.25)))
                    // 根据数值计算旋钮位置（范围0-100）
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

                // 文本单行显示，超出截断（预留箭头空间）
                let textMaxWidth = isShortEnum ? controlWidth - 16 : controlWidth - 8
                let displayText = truncatedText(text, font: valueFont, maxWidth: textMaxWidth)
                let textView = Text(displayText)
                    .font(.system(size: 8))
                    .foregroundColor(.primary)
                context.draw(textView, in: textRect.insetBy(dx: 4, dy: 2))

                if isShortEnum {
                    // 短文本：显示下拉箭头（模拟下拉菜单外观）
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

        // 输出插槽（节点右侧）：圆点在右边缘，标签在圆点左侧（节点内部右侧），右对齐，最大宽度70pt
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

        // 输入插槽（节点左侧）：圆点在左边缘，标签在圆点右侧（节点内部左侧），左对齐，最大宽度60pt
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

    /// 文本截断：超过最大宽度时显示省略号
    private func truncatedText(_ text: String, font: UIFont, maxWidth: CGFloat) -> String {
        let nsText = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = nsText.size(withAttributes: attributes).width
        if textWidth <= maxWidth { return text }
        // 逐步截断直到符合宽度
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
        // 3秒后取消高亮
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

    /// 命中测试：判断点击位置是否在滑块区域，返回滑块信息
    private func hitTestSlider(point: CGPoint) -> (nodeId: Int, index: Int)? {
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
                if hitRect.contains(point) {
                    return (node.id, index)
                }
            }
        }
        return nil
    }

    // MARK: - 插槽命中测试

    /// 命中测试：判断点击位置是否在输出插槽上，返回节点ID和插槽索引
    private func hitTestOutputSlot(point: CGPoint) -> (nodeId: Int, slotIndex: Int)? {
        let hitRadius: CGFloat = 12 // 扩大点击区域
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

    /// 命中测试：判断点击位置是否在输入插槽上，返回节点ID和插槽索引
    private func hitTestInputSlot(point: CGPoint) -> (nodeId: Int, slotIndex: Int)? {
        let hitRadius: CGFloat = 12 // 扩大点击区域
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

    // MARK: - 创建连线

    /// 创建连线：从源节点输出插槽到目标节点输入插槽
    private func createLink(from: (nodeId: Int, slotIndex: Int), to: (nodeId: Int, slotIndex: Int)) {
        // 不能连接到自己
        guard from.nodeId != to.nodeId else { return }

        // 生成唯一连线ID
        let newLinkId = (workflow.links.map { $0.id }.max() ?? 0) + 1

        // 获取源插槽的数据类型
        let sourceType = workflow.nodeMap[from.nodeId]?.outputs?[safe: from.slotIndex]?.type

        // 创建连线
        let newLink = LinkModel(
            id: newLinkId,
            sourceId: from.nodeId,
            sourceSlot: from.slotIndex,
            targetId: to.nodeId,
            targetSlot: to.slotIndex,
            linkType: sourceType
        )

        // 添加到工作流
        workflow.links.append(newLink)
    }

    /// 根据世界坐标X更新滑块数值（范围0-100，根据滑块位置比例计算）
    private func updateSliderValue(nodeId: Int, index: Int, worldX: CGFloat) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        var node = workflow.nodes[nodeIndex]
        guard var widgets = node.widgetsValues, index < widgets.count else { return }
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
        let sliderX = widgetX + labelWidth + 4 + numWidth + 6
        let sliderWidth = widgetWidth - labelWidth - 4 - numWidth - 6
        guard sliderWidth > 0 else { return }

        // 计算比例0-1
        var ratio = (worldX - sliderX) / sliderWidth
        ratio = max(0, min(1, ratio))
        // 数值范围0-100，取一位小数
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
    }

    /// 保存单参数编辑结果（严格保持原始值类型，避免类型转换导致显示异常）
    private func saveEditedWidget(nodeId: Int, index: Int, text: String) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        var node = workflow.nodes[nodeIndex]
        guard var widgets = node.widgetsValues, index < widgets.count else { return }
        let original = widgets[index]
        // 根据原始值的精确类型保存，严格保持类型一致
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
