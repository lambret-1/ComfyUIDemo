import SwiftUI

/// 画布小地图：右下角悬浮，显示节点分布与当前视野，支持点击/拖拽跳转、折叠展开
struct MiniMapView: View {
    /// 工作流数据
    let workflow: WorkflowModel
    /// 当前画布平移偏移
    let offset: CGPoint
    /// 当前画布缩放
    let zoom: CGFloat
    /// 主画布视图尺寸
    let viewSize: CGSize
    /// 点击小地图回调，返回画布世界坐标
    let onTap: (CGPoint) -> Void
    /// 拖拽小地图回调，返回画布世界坐标
    let onDrag: (CGPoint) -> Void

    /// 小地图尺寸
    private let mapWidth: CGFloat = 130
    private let mapHeight: CGFloat = 90
    /// 内边距
    private let padding: CGFloat = 6
    /// 折叠状态
    @State private var isCollapsed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if !isCollapsed {
                Canvas { context, size in
                    // 小地图背景（半透明，减少遮挡）
                    let bgRect = CGRect(origin: .zero, size: size)
                    context.fill(Path(bgRect), with: .color(Color.black.opacity(0.55)))
                    context.stroke(Path(bgRect), with: .color(.white.opacity(0.35)), lineWidth: 1)

                    // 计算所有节点（含分组）的包围盒
                    guard let box = contentBoundingBox else { return }
                    guard box.width > 0, box.height > 0 else { return }

                    // 等比缩放（Uniform Scale）
                    let availableW = size.width - padding * 2
                    let availableH = size.height - padding * 2
                    let scale = min(availableW / box.width, availableH / box.height)
                    let contentW = box.width * scale
                    let contentH = box.height * scale
                    let offsetX = (size.width - contentW) / 2 - box.minX * scale
                    let offsetY = (size.height - contentH) / 2 - box.minY * scale

                    // 绘制分组背景（底层）
                    for group in workflow.groups {
                        let gRect = CGRect(
                            x: group.frame.minX * scale + offsetX,
                            y: group.frame.minY * scale + offsetY,
                            width: max(group.frame.width * scale, 1),
                            height: max(group.frame.height * scale, 1)
                        )
                        context.fill(Path(gRect), with: .color(group.borderColor.opacity(0.25)))
                    }

                    // 绘制节点色块
                    for node in workflow.nodes {
                        let nodeRect = CGRect(
                            x: node.position.x * scale + offsetX,
                            y: node.position.y * scale + offsetY,
                            width: max(node.nodeSize.width * scale, 3),
                            height: max(node.nodeSize.height * scale, 3)
                        )
                        context.fill(Path(nodeRect), with: .color(node.headerColor))
                    }

                    // 绘制当前视野框（红色）
                    let viewWorldRect = CGRect(
                        x: -offset.x / zoom,
                        y: -offset.y / zoom,
                        width: viewSize.width / zoom,
                        height: viewSize.height / zoom
                    )
                    let viewMapRect = CGRect(
                        x: viewWorldRect.minX * scale + offsetX,
                        y: viewWorldRect.minY * scale + offsetY,
                        width: viewWorldRect.width * scale,
                        height: viewWorldRect.height * scale
                    )
                    context.stroke(Path(viewMapRect), with: .color(.red), lineWidth: 1.5)
                    context.fill(Path(viewMapRect), with: .color(.red.opacity(0.08)))
                }
                .frame(width: mapWidth, height: mapHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onDrag(mapToWorld(location: value.location))
                        }
                        .onEnded { value in
                            onTap(mapToWorld(location: value.location))
                        }
                )
            }

            // 折叠/展开按钮
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "map.fill" : "map")
                        .font(.system(size: 10))
                    if !isCollapsed {
                        Text("收起")
                            .font(.system(size: 10))
                    }
                }
                .frame(width: isCollapsed ? 36 : mapWidth, height: 24)
                .background(Color.black.opacity(0.55))
                .foregroundColor(.white)
            }
        }
        .cornerRadius(8)
        .shadow(radius: 4)
    }

    /// 将小地图坐标转换为画布世界坐标
    private func mapToWorld(location: CGPoint) -> CGPoint {
        guard let box = contentBoundingBox, box.width > 0, box.height > 0 else {
            return .zero
        }
        let availableW = mapWidth - padding * 2
        let availableH = mapHeight - padding * 2
        let scale = min(availableW / box.width, availableH / box.height)
        let contentW = box.width * scale
        let contentH = box.height * scale
        let offsetX = (mapWidth - contentW) / 2 - box.minX * scale
        let offsetY = (mapHeight - contentH) / 2 - box.minY * scale
        return CGPoint(
            x: (location.x - offsetX) / scale,
            y: (location.y - offsetY) / scale
        )
    }

    /// 所有节点与分组的包围盒
    private var contentBoundingBox: CGRect? {
        var boxes: [CGRect] = workflow.nodes.map {
            CGRect(origin: $0.position, size: $0.nodeSize)
        }
        boxes.append(contentsOf: workflow.groups.map { $0.frame })
        guard !boxes.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for box in boxes {
            guard box.width > 0, box.height > 0 else { continue }
            minX = min(minX, box.minX)
            minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }
        guard minX != .greatestFiniteMagnitude else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
