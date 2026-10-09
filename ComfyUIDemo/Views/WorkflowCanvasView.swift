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
}

/// 节点ID包装器，用于sheet(item:)
private struct NodeIDWrapper: Identifiable {
    let id: Int
}
