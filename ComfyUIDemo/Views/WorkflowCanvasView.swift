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

                    // 层级3：节点
                    drawNodes(context: context, highlightedId: highlightedNodeId)
                }
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGPoint(
                                    x: lastOffset.x + value.translation.width,
                                    y: lastOffset.y + value.translation.height
                                )
                            }
                            .onEnded { _ in
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
                    selectedNodeId = workflow.nodes.first { node in
                        CGRect(origin: node.position, size: node.nodeSize).contains(worldPoint)
                    }?.id
                }
                .sheet(item: Binding(
                    get: { selectedNodeId.map { NodeIDWrapper(id: $0) } },
                    set: { selectedNodeId = $0?.id }
                )) { wrapper in
                    NodeDetailSheet(workflow: $workflow, nodeId: wrapper.id)
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

            // 高亮节点发光效果
            if highlightedId == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -6, dy: -6)), with: .color(.yellow.opacity(0.4)))
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

            // 控件区域（居中，避开左右两侧插槽标签区域）
            // 左侧输入插槽标签最大宽度100pt + 圆点5pt + 间距 = 115pt
            // 右侧输出插槽标签最大宽度120pt + 圆点5pt + 间距 = 135pt
            let widgetTop = headerRect.maxY + 6
            let widgetBottom = rect.maxY - 20
            let leftInset: CGFloat = 115
            let rightInset: CGFloat = 135
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

    /// 绘制节点内部控件（只读展示，带真实参数名标签，按类型渲染不同控件外观）
    private func drawWidgets(context: GraphicsContext, widgets: [WidgetValue], names: [String], in rect: CGRect) {
        let labelHeight: CGFloat = 10
        let controlHeight: CGFloat = 16
        let rowSpacing: CGFloat = 5
        let rowHeight = labelHeight + controlHeight + rowSpacing
        var currentY = rect.minY

        for (index, widget) in widgets.enumerated() {
            // 计算当前控件需要的高度
            var neededControlHeight = controlHeight
            if case .text = widget.widgetKind {
                let font = UIFont.systemFont(ofSize: 8)
                let textHeight = widget.displayString.boundingRect(
                    with: CGSize(width: rect.width - 8, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font],
                    context: nil
                ).height
                neededControlHeight = max(controlHeight, ceil(textHeight) + 4)
            }
            let totalRowHeight = labelHeight + neededControlHeight + rowSpacing

            guard currentY + totalRowHeight <= rect.maxY else {
                if currentY < rect.maxY {
                    let remaining = widgets.count - index
                    let moreText = Text("… +\(remaining) 更多参数")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    context.draw(moreText, in: CGRect(x: rect.minX, y: currentY, width: rect.width, height: 14))
                }
                break
            }

            // 参数名标签（上方，小号灰色）
            let rawName = index < names.count ? names[index] : "参数\(index + 1)"
            let paramName = SlotLocalization.localized(for: rawName)
            let labelText = Text(paramName)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            context.draw(labelText, in: CGRect(x: rect.minX, y: currentY, width: rect.width, height: labelHeight))

            let controlY = currentY + labelHeight + 1

            switch widget.widgetKind {
            case .toggle:
                let isOn = widget.boolValue
                let toggleRect = CGRect(x: rect.minX, y: controlY, width: 28, height: 14)
                let toggleShape = RoundedRectangle(cornerRadius: 7)
                context.fill(toggleShape.path(in: toggleRect), with: .color(isOn ? .green : .gray.opacity(0.4)))
                let knobX = isOn ? toggleRect.maxX - 11 : toggleRect.minX + 2
                let knobRect = CGRect(x: knobX, y: toggleRect.minY + 1, width: 11, height: 12)
                context.fill(Path(ellipseIn: knobRect), with: .color(.white))
                let statusText = Text(isOn ? "开" : "关")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                context.draw(statusText, at: CGPoint(x: toggleRect.maxX + 4, y: controlY + 7), anchor: .leading)

            case .number:
                // 数字框 + 迷你滑块条
                let numWidth: CGFloat = 52
                let numRect = CGRect(x: rect.minX, y: controlY, width: numWidth, height: controlHeight)
                let numShape = RoundedRectangle(cornerRadius: 4)
                context.fill(numShape.path(in: numRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(numShape.path(in: numRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                let numText = Text(widget.displayString)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                context.draw(numText, in: numRect.insetBy(dx: 4, dy: 1))

                // 迷你滑块条（仅外观，不可交互）
                let sliderX = numRect.maxX + 6
                let sliderWidth = max(0, rect.width - sliderX)
                if sliderWidth > 20 {
                    let sliderRect = CGRect(x: sliderX, y: controlY + 6, width: sliderWidth, height: 4)
                    context.fill(Path(roundedRect: sliderRect, cornerSize: CGSize(width: 2, height: 2)),
                               with: .color(.gray.opacity(0.25)))
                    // 滑块圆点（默认在中间位置）
                    let knobX = sliderX + sliderWidth * 0.5
                    let knobRect = CGRect(x: knobX - 4, y: controlY + 3, width: 8, height: 10)
                    context.fill(Path(ellipseIn: knobRect), with: .color(.blue))
                }

            case .text:
                let text = widget.displayString
                let isShortEnum = text.count <= 20 && !text.contains(" ") && !text.contains("\n")
                let textRect = CGRect(x: rect.minX, y: controlY, width: rect.width, height: neededControlHeight)
                let textShape = RoundedRectangle(cornerRadius: 4)
                context.fill(textShape.path(in: textRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(textShape.path(in: textRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)

                if isShortEnum {
                    // 短文本：显示下拉箭头（模拟下拉菜单外观）
                    let textView = Text(text)
                        .font(.system(size: 8))
                        .foregroundColor(.primary)
                    context.draw(textView, in: textRect.insetBy(dx: 4, dy: 2))
                    // 下拉箭头
                    let arrowX = textRect.maxX - 12
                    let arrowPath = Path { p in
                        p.move(to: CGPoint(x: arrowX, y: controlY + 5))
                        p.addLine(to: CGPoint(x: arrowX + 4, y: controlY + 9))
                        p.addLine(to: CGPoint(x: arrowX + 8, y: controlY + 5))
                    }
                    context.stroke(arrowPath, with: .color(.gray), lineWidth: 1)
                } else {
                    // 长文本：多行显示
                    let textView = Text(text)
                        .font(.system(size: 8))
                        .foregroundColor(.primary)
                    context.draw(textView, in: textRect.insetBy(dx: 4, dy: 2))
                }
            }

            currentY += totalRowHeight
        }
    }

    // MARK: - 插槽绘制与定位

    /// 绘制节点的输入/输出插槽及名称标签
    private func drawSlots(context: GraphicsContext, node: NodeModel) {
        let dotSize: CGFloat = 10
        let labelFont = UIFont.systemFont(ofSize: 10)

        // 输出插槽（节点右侧）：圆点在右边缘，标签在圆点左侧（节点内部右侧），右对齐，最大宽度120pt
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
                    let maxWidth: CGFloat = 120
                    let displayName = truncatedText(localized, font: labelFont, maxWidth: maxWidth)
                    let nameText = Text(displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    // 标签在圆点左侧（节点内部），右对齐
                    let labelPoint = CGPoint(x: point.x - dotSize / 2 - 5, y: point.y)
                    context.draw(nameText, at: labelPoint, anchor: .trailing)
                }
            }
        }

        // 输入插槽（节点左侧）：圆点在左边缘，标签在圆点右侧（节点内部左侧），左对齐，最大宽度100pt
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
                    let maxWidth: CGFloat = 100
                    let displayName = truncatedText(localized, font: labelFont, maxWidth: maxWidth)
                    let nameText = Text(displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    // 标签在圆点右侧（节点内部），左对齐
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
