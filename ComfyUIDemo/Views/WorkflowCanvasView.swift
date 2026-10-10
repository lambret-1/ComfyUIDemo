import SwiftUI

/// 工作流画布视图：使用 SwiftUI Canvas 高性能渲染分组、连线、节点与控件
/// 支持双指缩放、单指拖拽、节点点击查看详情、重置视角
struct WorkflowCanvasView: View {
    /// 工作流数据绑定（支持弹窗修改参数后同步画布与父视图）
    @Binding var workflow: WorkflowModel
    /// 当前平移偏移
    @State var offset: CGPoint = .zero
    /// 当前缩放比例
    @State var zoom: CGFloat = 1.0
    /// 上一次手势结束时的平移偏移
    @State var lastOffset: CGPoint = .zero
    /// 上一次手势结束时的缩放比例
    @State var lastZoom: CGFloat = 1.0
    /// 当前选中的节点ID
    @State var selectedNodeId: Int?
    /// 是否已经执行过初始适配
    @State var hasFitted = false
    /// 当前视图尺寸
    @State var viewSize: CGSize = .zero
    /// 高亮节点ID（搜索定位时使用）
    @State var highlightedNodeId: Int?
    /// 当前正在编辑的单个参数（nodeId + widgetIndex）
    @State var editingWidget: (nodeId: Int, index: Int)?
    /// 单参数编辑弹窗的输入文本
    @State var editingText: String = ""
    /// 是否显示单参数编辑弹窗
    @State var showWidgetEditor: Bool = false
    /// 连线状态：是否正在连线
    @State var isConnecting: Bool = false
    /// 连线起点（源节点ID + 输出插槽索引）
    @State var connectingFrom: (nodeId: Int, slotIndex: Int)?
    /// 连线当前终点（手指位置，世界坐标）
    @State var connectingTo: CGPoint?
    /// 连线起点的世界坐标（用于绘制预览线）
    @State var connectingFromPoint: CGPoint?
    /// 当前被吸附的输入插槽（用于高亮显示和自动吸附）
    @State var snappedInputSlot: (nodeId: Int, slotIndex: Int)?
    /// 正在拖动的节点ID（节点自由移动）
    @State var draggingNodeId: Int?
    /// 拖动开始时节点的位置（世界坐标）
    @State var dragStartNodePos: CGPoint?
    /// 拖动开始时手指的位置（世界坐标）
    @State var dragStartTouchPos: CGPoint?
    /// 拖动偏移量（拖动过程中仅更新此轻量状态，不修改 workflow）
    @State var draggingOffset: CGSize = .zero

    // MARK: - 性能优化状态

    /// 是否正在交互（拖动/平移中）：交互时降级渲染，跳过非必要文字
    @State var isInteracting: Bool = false
    /// 节点渲染数据缓存：预计算尺寸、插槽位置、截断文本，避免每帧重复计算
    @State var renderCache: [Int: NodeRenderData] = [:]

    // MARK: - 手势区分状态（点击 vs 拖动）
    /// 本次手势是否真正移动过（用于区分点击与拖动）
    @State var gestureDidMove: Bool = false
    /// 本次手势的起始屏幕坐标
    @State var gestureStartLocation: CGPoint?
    /// 当前拖动模式（首次移动超阈值时锁定，避免每帧重新判断导致抖动）
    @State var dragMode: DragMode = .none

    // MARK: - 拖动模式枚举
    /// 拖动意图模式：首次移动超过3pt时根据起点+方向一次性决定，之后锁定
    enum DragMode {
        /// 尚未决定（移动未超阈值）
        case none
        /// 拖动节点
        case node
        /// 拖动滑块（水平拖动number控件）
        case slider
        /// 平移画布
        case canvas
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // 背景网格层（静态独立视图，drawingGroup光栅化缓存，不随节点拖动重绘）
                Canvas { context, size in
                    drawGrid(context: context, viewSize: size)
                }
                .drawingGroup()
                // 主画布层（分组+连线+节点+控件，动态内容）
                Canvas { context, size in
                    // 记录视图尺寸
                    if viewSize != size {
                        DispatchQueue.main.async { viewSize = size }
                    }

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
                            actualToPoint = cachedSlotPosition(node: snappedNode,
                                                               slotIndex: snapped.slotIndex,
                                                               isOutput: false, context: context)
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
                                let newZoom = CanvasMath.clamp(
                                    lastZoom * value.magnification,
                                    min: CanvasMath.minZoom,
                                    max: CanvasMath.maxZoom
                                )
                                // 以双指中心为锚点缩放：保持锚点在屏幕上的位置不变
                                let anchor = value.location
                                // 锚点对应的世界坐标（基于当前 offset 和 zoom）
                                let worldX = (anchor.x - offset.x) / zoom
                                let worldY = (anchor.y - offset.y) / zoom
                                // 调整 offset 使锚点屏幕位置不变
                                offset = CGPoint(
                                    x: anchor.x - worldX * newZoom,
                                    y: anchor.y - worldY * newZoom
                                )
                                zoom = newZoom
                                isInteracting = true
                            }
                            .onEnded { _ in
                                lastZoom = zoom
                                lastOffset = offset
                                isInteracting = false
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
                            rebuildRenderCache()
                            fitToView(size: geometry.size)
                        }
                    }
                }
                // workflow 结构变化时重建渲染缓存
                .onChange(of: workflow) { _ in
                    rebuildRenderCache()
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
