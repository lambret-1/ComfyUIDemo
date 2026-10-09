import SwiftUI

/// 工作流画布视图：使用 SwiftUI Canvas 高性能渲染节点与连线
/// 支持双指缩放、单指拖拽、节点点击查看详情、重置视角
struct WorkflowCanvasView: View {
    /// 工作流数据
    let workflow: WorkflowModel
    /// 当前平移偏移
    @State private var offset: CGPoint = .zero
    /// 当前缩放比例
    @State private var zoom: CGFloat = 1.0
    /// 上一次手势结束时的平移偏移（用于累加）
    @State private var lastOffset: CGPoint = .zero
    /// 上一次手势结束时的缩放比例（用于累加）
    @State private var lastZoom: CGFloat = 1.0
    /// 当前选中的节点（用于弹出详情）
    @State private var selectedNode: NodeModel?
    /// 视图尺寸（用于适配计算）
    @State private var viewSize: CGSize = .zero
    /// 是否已经执行过初始适配
    @State private var hasFitted = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // 记录视图尺寸
                if viewSize != size {
                    DispatchQueue.main.async {
                        viewSize = size
                    }
                }

                // 绘制背景网格（在屏幕坐标系，不随画布变换）
                drawGrid(context: context, viewSize: size)

                // 高性能：在 Canvas 内部执行矩阵变换，避免外层 scaleEffect 触发离屏渲染
                context.translateBy(x: offset.x, y: offset.y)
                context.scaleBy(x: zoom, y: zoom)

                // 先绘制连线（底层）
                drawLinks(context: context)

                // 再绘制节点（上层）
                drawNodes(context: context)
            }
            .gesture(
                // 同时识别拖拽与缩放手势，互不干扰
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
                            let newZoom = CanvasMath.clamp(
                                lastZoom * value,
                                min: CanvasMath.minZoom,
                                max: CanvasMath.maxZoom
                            )
                            zoom = newZoom
                        }
                        .onEnded { _ in
                            lastZoom = zoom
                        }
                )
            )
            .onTapGesture { location in
                // 将屏幕坐标反向变换为画布世界坐标
                let worldX = (location.x - offset.x) / zoom
                let worldY = (location.y - offset.y) / zoom
                let worldPoint = CGPoint(x: worldX, y: worldY)

                // 命中检测：遍历节点，找到包含点击坐标的节点
                selectedNode = workflow.nodes.first { node in
                    CGRect(origin: node.position, size: node.nodeSize).contains(worldPoint)
                }
            }
            .sheet(item: $selectedNode) { node in
                NodeDetailSheet(node: node)
            }
            .overlay(alignment: .topTrailing) {
                Button("重置视角") {
                    fitToView(size: geometry.size)
                }
                .buttonStyle(.borderedProminent)
                .padding(8)
            }
            .onAppear {
                // 首次出现时自动适配视图
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
            let linkColor = colorForLinkType(link.linkType)
            context.stroke(path, with: .color(linkColor), lineWidth: 2 / zoom)
        }
    }

    /// 生成两点间的三次贝塞尔曲线路径（ComfyUI 风格横向连线）
    private func bezierLinkPath(from: CGPoint, to: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            let controlOffset = max(abs(to.x - from.x) * 0.5, 40)
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + controlOffset, y: from.y),
                control2: CGPoint(x: to.x - controlOffset, y: to.y)
            )
        }
    }

    /// 根据连线数据类型返回颜色
    private func colorForLinkType(_ type: String?) -> Color {
        guard let type = type else { return .blue }
        switch type.uppercased() {
        case "MODEL": return .orange
        case "CLIP": return .green
        case "VAE": return .purple
        case "LATENT": return .pink
        case "IMAGE": return .blue
        case "CONDITIONING": return .yellow
        case "MASK": return .gray
        default: return .blue
        }
    }

    // MARK: - 节点绘制

    /// 绘制所有节点
    private func drawNodes(context: GraphicsContext) {
        for node in workflow.nodes {
            let rect = CGRect(origin: node.position, size: node.nodeSize)
            let shape = RoundedRectangle(cornerRadius: 8)

            // 节点背景
            context.fill(shape.path(in: rect), with: .color(Color(.secondarySystemBackground)))
            // 节点边框
            context.stroke(shape.path(in: rect), with: .color(.teal), lineWidth: 2 / zoom)

            // 节点标题栏（顶部色带）
            let headerRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: min(28, rect.height * 0.3)
            )
            context.fill(shape.path(in: headerRect), with: .color(.teal.opacity(0.6)))

            // 节点标题文本
            let titleText = Text(node.displayTitle)
                .font(.system(size: 12 / zoom, weight: .semibold))
                .foregroundColor(.white)
            context.draw(titleText, in: headerRect.insetBy(dx: 6 / zoom, dy: 2 / zoom))

            // 节点类型文本（标题下方）
            let typeRect = CGRect(
                x: rect.minX,
                y: headerRect.maxY,
                width: rect.width,
                height: rect.height - headerRect.height
            )
            let typeText = Text(node.type)
                .font(.system(size: 10 / zoom))
                .foregroundColor(.secondary)
            context.draw(typeText, in: typeRect.insetBy(dx: 6 / zoom, dy: 4 / zoom))

            // 绘制插槽圆点
            drawSlots(context: context, node: node)
        }
    }

    // MARK: - 插槽绘制与定位

    /// 绘制节点的输入/输出插槽
    private func drawSlots(context: GraphicsContext, node: NodeModel) {
        // 输出插槽（节点右侧）
        if let outputs = node.outputs {
            for (index, _) in outputs.enumerated() {
                let point = getSlotPosition(node: node, slotIndex: index, isOutput: true)
                let dotSize: CGFloat = 8 / zoom
                let dotRect = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(.orange))
                context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1 / zoom)
            }
        }

        // 输入插槽（节点左侧）
        if let inputs = node.inputs {
            for (index, _) in inputs.enumerated() {
                let point = getSlotPosition(node: node, slotIndex: index, isOutput: false)
                let dotSize: CGFloat = 8 / zoom
                let dotRect = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(.purple))
                context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1 / zoom)
            }
        }
    }

    /// 计算插槽在画布中的坐标
    /// - Parameters:
    ///   - node: 所属节点
    ///   - slotIndex: 插槽索引
    ///   - isOutput: 是否为输出插槽（输出在右，输入在左）
    /// - Returns: 插槽中心点坐标
    private func getSlotPosition(node: NodeModel, slotIndex: Int, isOutput: Bool) -> CGPoint {
        let rect = CGRect(origin: node.position, size: node.nodeSize)
        let headerHeight = min(28, rect.height * 0.3)
        let slotAreaTop = rect.minY + headerHeight + 8
        let slotGap: CGFloat = 18
        let y = slotAreaTop + CGFloat(slotIndex) * slotGap

        if isOutput {
            return CGPoint(x: rect.maxX, y: y)
        } else {
            return CGPoint(x: rect.minX, y: y)
        }
    }

    // MARK: - 背景网格

    /// 绘制画布背景网格（屏幕坐标系，不随变换移动）
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

    /// 重置视角：计算包围盒并居中适配
    private func fitToView(size: CGSize) {
        let box = CanvasMath.getBoundingBox(nodes: workflow.nodes)
        guard box.width > 0, box.height > 0 else {
            zoom = 1.0
            offset = .zero
            lastZoom = 1.0
            lastOffset = .zero
            return
        }

        zoom = CanvasMath.computeFitScale(box: box, viewSize: size)
        lastZoom = zoom

        // 居中偏移：使包围盒中心对齐视图中心
        offset = CGPoint(
            x: size.width / 2 - (box.midX * zoom),
            y: size.height / 2 - (box.midY * zoom)
        )
        lastOffset = offset
    }
}
