import SwiftUI

/// 画布小地图：右下角悬浮，显示节点分布与当前视野
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

    /// 小地图尺寸
    private let mapWidth: CGFloat = 120
    private let mapHeight: CGFloat = 84

    var body: some View {
        Canvas { context, size in
            // 小地图背景
            let bgRect = CGRect(origin: .zero, size: size)
            context.fill(Path(bgRect), with: .color(Color.black.opacity(0.6)))
            context.stroke(Path(bgRect), with: .color(.white.opacity(0.3)), lineWidth: 1)

            // 计算节点包围盒与缩放比例
            guard let box = nodeBoundingBox else { return }
            let scaleX = (size.width - 8) / max(box.width, 1)
            let scaleY = (size.height - 8) / max(box.height, 1)
            let scale = min(scaleX, scaleY)
            let mapOffsetX = (size.width - box.width * scale) / 2 - box.minX * scale
            let mapOffsetY = (size.height - box.height * scale) / 2 - box.minY * scale

            // 绘制节点色块
            for node in workflow.nodes {
                let nodeRect = CGRect(
                    x: node.position.x * scale + mapOffsetX,
                    y: node.position.y * scale + mapOffsetY,
                    width: max(node.nodeSize.width * scale, 2),
                    height: max(node.nodeSize.height * scale, 2)
                )
                context.fill(Path(nodeRect), with: .color(node.headerColor.opacity(0.8)))
            }

            // 绘制当前视野框（红色）
            let viewWorldRect = CGRect(
                x: -offset.x / zoom,
                y: -offset.y / zoom,
                width: viewSize.width / zoom,
                height: viewSize.height / zoom
            )
            let viewMapRect = CGRect(
                x: viewWorldRect.minX * scale + mapOffsetX,
                y: viewWorldRect.minY * scale + mapOffsetY,
                width: viewWorldRect.width * scale,
                height: viewWorldRect.height * scale
            )
            context.stroke(Path(viewMapRect), with: .color(.red), lineWidth: 1.5)
        }
        .frame(width: mapWidth, height: mapHeight)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { location in
            // 将小地图点击坐标转换为画布世界坐标
            guard let box = nodeBoundingBox else { return }
            let scaleX = (mapWidth - 8) / max(box.width, 1)
            let scaleY = (mapHeight - 8) / max(box.height, 1)
            let scale = min(scaleX, scaleY)
            let mapOffsetX = (mapWidth - box.width * scale) / 2 - box.minX * scale
            let mapOffsetY = (mapHeight - box.height * scale) / 2 - box.minY * scale

            let worldX = (location.x - mapOffsetX) / scale
            let worldY = (location.y - mapOffsetY) / scale
            onTap(CGPoint(x: worldX, y: worldY))
        }
    }

    /// 所有节点的包围盒
    private var nodeBoundingBox: CGRect? {
        guard !workflow.nodes.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for node in workflow.nodes {
            let r = CGRect(origin: node.position, size: node.nodeSize)
            minX = min(minX, r.minX)
            minY = min(minY, r.minY)
            maxX = max(maxX, r.maxX)
            maxY = max(maxY, r.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
