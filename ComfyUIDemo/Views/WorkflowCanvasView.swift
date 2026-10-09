import SwiftUI

/// 工作流画布视图：使用 SwiftUI Canvas 高性能渲染分组、连线、节点与控件
/// 支持双指缩放、单指拖拽、节点点击查看详情、重置视角
/// MVVM架构：状态和业务逻辑由WorkflowViewModel管理，本视图只负责渲染和手势转发
struct WorkflowCanvasView: View {
    /// 工作流视图模型（MVVM架构，统一管理状态和业务逻辑）
    @ObservedObject var viewModel: WorkflowViewModel
    /// 当前选中的节点ID（详情页）
    @State private var selectedNodeId: Int?
    /// 是否已经执行过初始适配
    @State private var hasFitted = false
    /// 当前视图尺寸
    @State private var viewSize: CGSize = .zero

    /// 便捷访问：工作流数据
    private var workflow: WorkflowModel { viewModel.workflow }
    /// 便捷访问：视口偏移
    private var offset: CGPoint { viewModel.viewport.offset }
    /// 便捷访问：缩放比例
    private var zoom: CGFloat { viewModel.viewport.scale }
    /// 便捷访问：选中编辑的节点ID
    private var selectedNodeIdForEdit: Int? { viewModel.selectedNodeID }
    /// 便捷访问：高亮节点ID
    private var highlightedNodeId: Int? { viewModel.highlightedNodeID }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // L0-L2: Canvas层（背景网格 + 分组 + 连线）
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
                }
                // 画布平移手势（节点拖动使用highPriorityGesture，会优先于此手势）
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                viewModel.applyPan(translation: value.translation)
                            }
                            .onEnded { _ in
                                viewModel.saveViewportState()
                            },
                        MagnificationGesture()
                            .onChanged { value in
                                viewModel.applyZoom(magnification: value)
                            }
                            .onEnded { _ in
                                viewModel.saveViewportState()
                            }
                    )
                )
                // 点击画布空白区域 → 取消选中
                .onTapGesture {
                    viewModel.selectNode(nil)
                }

                // L3: 节点层（SwiftUI视图，支持自由拖动和参数直接编辑）
                nodesLayer

                // 详情页sheet
                .sheet(item: Binding(
                    get: { selectedNodeId.map { NodeIDWrapper(id: $0) } },
                    set: { selectedNodeId = $0?.id }
                )) { wrapper in
                    NodeDetailSheet(workflow: $viewModel.workflow, nodeId: wrapper.id)
                }
                .onReceive(NotificationCenter.default.publisher(for: .resetCanvasView)) { _ in
                    viewModel.fitToView(size: geometry.size)
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusNode)) { notification in
                    if let nodeId = notification.object as? Int {
                        viewModel.focusOnNode(nodeId, viewSize: geometry.size)
                    }
                }
                .onAppear {
                    if !hasFitted {
                        hasFitted = true
                        DispatchQueue.main.async {
                            viewModel.fitToView(size: geometry.size)
                        }
                    }
                }

                // L4: 小地图（右下角悬浮）
                MiniMapView(
                    workflow: workflow,
                    offset: offset,
                    zoom: zoom,
                    viewSize: geometry.size,
                    onTap: { worldPoint in
                        let newOffset = CGPoint(
                            x: geometry.size.width / 2 - worldPoint.x * zoom,
                            y: geometry.size.height / 2 - worldPoint.y * zoom
                        )
                        viewModel.viewport.offset = newOffset
                        viewModel.viewport.lastOffset = newOffset
                    },
                    onDrag: { worldPoint in
                        let newOffset = CGPoint(
                            x: geometry.size.width / 2 - worldPoint.x * zoom,
                            y: geometry.size.height / 2 - worldPoint.y * zoom
                        )
                        viewModel.viewport.offset = newOffset
                        viewModel.viewport.lastOffset = newOffset
                    }
                )
                .padding(12)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 节点层

    /// 节点层：使用SwiftUI视图渲染所有节点，支持自由拖动和参数编辑
    private var nodesLayer: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(workflow.nodes) { node in
                    let screenX = node.position.x * zoom + offset.x
                    let screenY = node.position.y * zoom + offset.y

                    NodeView(
                        node: node,
                        isSelected: selectedNodeIdForEdit == node.id,
                        isHighlighted: highlightedNodeId == node.id,
                        viewModel: viewModel,
                        onTap: {
                            viewModel.selectNode(node.id)
                        },
                        onInfo: {
                            selectedNodeId = node.id
                        },
                        onDrag: { translation in
                            viewModel.moveNode(id: node.id, by: translation)
                        }
                    )
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(x: screenX, y: screenY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - 背景网格

    /// 绘制背景网格（屏幕坐标系，不随缩放变化）
    private func drawGrid(context: GraphicsContext, viewSize: CGSize) {
        let gridSize: CGFloat = 20
        let path = Path { p in
            var x: CGFloat = 0
            while x <= viewSize.width {
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: viewSize.height))
                x += gridSize
            }
            var y: CGFloat = 0
            while y <= viewSize.height {
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: viewSize.width, y: y))
                y += gridSize
            }
        }
        context.stroke(path, with: .color(Color.gray.opacity(0.15)), lineWidth: 0.5)
    }

    // MARK: - 插槽位置计算

    /// 计算插槽在画布坐标系中的位置（用于连线端点）
    private func getSlotPosition(node: NodeModel, slotIndex: Int, isOutput: Bool) -> CGPoint {
        let headerHeight: CGFloat = 30
        let rowHeight: CGFloat = 22
        let slotY = node.position.y + headerHeight + 6 + CGFloat(slotIndex) * rowHeight + 8

        if isOutput {
            return CGPoint(x: node.position.x + node.nodeSize.width, y: slotY)
        } else {
            return CGPoint(x: node.position.x, y: slotY)
        }
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
