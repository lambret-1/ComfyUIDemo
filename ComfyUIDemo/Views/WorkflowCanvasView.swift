import SwiftUI

/// 工作流画布视图：使用 SwiftUI Canvas 高性能渲染分组、连线、节点与控件
/// 支持双指缩放、单指拖拽、节点点击查看详情、重置视角
struct WorkflowCanvasView: View {
    /// 工作流数据
    let workflow: WorkflowModel
    /// 当前平移偏移
    @State private var offset: CGPoint = .zero
    /// 当前缩放比例
    @State private var zoom: CGFloat = 1.0
    /// 上一次手势结束时的平移偏移
    @State private var lastOffset: CGPoint = .zero
    /// 上一次手势结束时的缩放比例
    @State private var lastZoom: CGFloat = 1.0
    /// 当前选中的节点
    @State private var selectedNode: NodeModel?
    /// 是否已经执行过初始适配
    @State private var hasFitted = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
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
                drawNodes(context: context)
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
                selectedNode = workflow.nodes.first { node in
                    CGRect(origin: node.position, size: node.nodeSize).contains(worldPoint)
                }
            }
            .sheet(item: $selectedNode) { node in
                NodeDetailSheet(node: node, workflow: workflow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetCanvasView)) { _ in
                fitToView(size: geometry.size)
            }
            .onAppear {
                if !hasFitted {
                    hasFitted = true
                    DispatchQueue.main.async {
                        fitToView(size: geometry.size)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 分组绘制

    /// 绘制分组背景框与标题（最底层）
    private func drawGroups(context: GraphicsContext) {
        for group in workflow.groups {
            let rect = group.frame
            guard rect.width > 0, rect.height > 0 else { continue }

            let shape = RoundedRectangle(cornerRadius: 12)
            context.fill(shape.path(in: rect), with: .color(group.groupColor))
            context.stroke(shape.path(in: rect), with: .color(group.borderColor), lineWidth: 1.5)

            let titleText = Text(group.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(group.borderColor)
            let titleRect = CGRect(
                x: rect.minX + 12,
                y: rect.minY + 8,
                width: rect.width - 24,
                height: 20
            )
            context.draw(titleText, in: titleRect)
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
            let controlOffset = max(abs(to.x - from.x) * 0.5, 50)
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + controlOffset, y: from.y),
                control2: CGPoint(x: to.x - controlOffset, y: to.y)
            )
        }
    }

    // MARK: - 节点绘制

    /// 绘制所有节点
    private func drawNodes(context: GraphicsContext) {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            let shape = RoundedRectangle(cornerRadius: 8)

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

            // 控件区域
            let widgetTop = headerRect.maxY + 6
            let widgetBottom = rect.maxY - 20
            if let widgets = node.widgetsValues, !widgets.isEmpty {
                drawWidgets(
                    context: context,
                    widgets: widgets,
                    in: CGRect(x: rect.minX + 8, y: widgetTop, width: rect.width - 16, height: widgetBottom - widgetTop)
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

    /// 绘制节点内部控件（只读展示）
    private func drawWidgets(context: GraphicsContext, widgets: [WidgetValue], in rect: CGRect) {
        let rowHeight: CGFloat = 18
        var currentY = rect.minY

        for (_, widget) in widgets.enumerated() {
            guard currentY + rowHeight <= rect.maxY else {
                if currentY < rect.maxY {
                    let moreText = Text("… 更多参数")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    context.draw(moreText, in: CGRect(x: rect.minX, y: currentY, width: rect.width, height: rowHeight))
                }
                break
            }

            let rowRect = CGRect(x: rect.minX, y: currentY, width: rect.width, height: rowHeight)

            switch widget.widgetKind {
            case .toggle:
                let isOn = widget.displayString == "是"
                let toggleRect = CGRect(x: rect.minX, y: currentY + 2, width: 32, height: 14)
                let toggleShape = RoundedRectangle(cornerRadius: 7)
                context.fill(toggleShape.path(in: toggleRect), with: .color(isOn ? .green : .gray.opacity(0.4)))
                let knobX = isOn ? toggleRect.maxX - 12 : toggleRect.minX + 2
                let knobRect = CGRect(x: knobX, y: toggleRect.minY + 1, width: 12, height: 12)
                context.fill(Path(ellipseIn: knobRect), with: .color(.white))

            case .number:
                let numRect = CGRect(x: rect.minX, y: currentY + 1, width: min(rect.width, 80), height: 16)
                let numShape = RoundedRectangle(cornerRadius: 4)
                context.fill(numShape.path(in: numRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(numShape.path(in: numRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                let numText = Text(widget.displayString)
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                context.draw(numText, in: numRect.insetBy(dx: 4, dy: 1))

            case .text:
                let text = widget.displayString
                let displayText = text.count > 24 ? String(text.prefix(24)) + "…" : text
                let textView = Text(displayText)
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                context.draw(textView, in: rowRect)
            }

            currentY += rowHeight + 2
        }
    }

    // MARK: - 插槽绘制与定位

    /// 绘制节点的输入/输出插槽及名称标签
    private func drawSlots(context: GraphicsContext, node: NodeModel) {
        if let outputs = node.outputs {
            for (index, slot) in outputs.enumerated() {
                let point = getSlotPosition(node: node, slotIndex: index, isOutput: true)
                let dotSize: CGFloat = 10
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
                    let nameText = Text(slotName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    let labelPoint = CGPoint(x: point.x - dotSize / 2 - 4, y: point.y)
                    context.draw(nameText, at: labelPoint, anchor: .trailing)
                }
            }
        }

        if let inputs = node.inputs {
            for (index, slot) in inputs.enumerated() {
                let point = getSlotPosition(node: node, slotIndex: index, isOutput: false)
                let dotSize: CGFloat = 10
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
                    let nameText = Text(slotName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    let labelPoint = CGPoint(x: point.x + dotSize / 2 + 4, y: point.y)
                    context.draw(nameText, at: labelPoint, anchor: .leading)
                }
            }
        }
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
}

// MARK: - 数组安全下标

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
