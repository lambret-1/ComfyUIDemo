import SwiftUI

/// 节点库菜单：按分类展示所有可用节点，点击后创建新节点
struct NodeLibraryMenu: View {
    /// 选择节点回调
    let onSelect: (NodeDefinition) -> Void
    /// 关闭回调
    let onDismiss: () -> Void
    /// 搜索关键词
    @State private var searchText: String = ""

    /// 过滤后的节点列表
    private var filteredNodes: [NodeDefinition] {
        let all = Array(MiniMaxH3NodeDatabase.allNodes.values)
        guard !searchText.isEmpty else { return all }
        let keyword = searchText.lowercased()
        return all.filter { node in
            node.displayName.lowercased().contains(keyword) ||
            node.type.lowercased().contains(keyword) ||
            node.category.rawValue.contains(keyword)
        }
    }

    /// 按分类分组的节点列表
    private var groupedNodes: [(NodeCategory, [NodeDefinition])] {
        let grouped = Dictionary(grouping: filteredNodes) { $0.category }
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedNodes, id: \.0) { category, nodes in
                    Section {
                        ForEach(nodes, id: \.type) { node in
                            Button {
                                onSelect(node)
                            } label: {
                                HStack(spacing: 12) {
                                    // 节点颜色标识
                                    Circle()
                                        .fill(Color(hex: node.colorHex) ?? .gray)
                                        .frame(width: 12, height: 12)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(node.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(node.type)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let desc = node.description {
                                            Text(desc)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: categoryIcon(category))
                            Text(category.rawValue)
                                .font(.headline)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索节点名称或类型")
            .navigationTitle("节点库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        onDismiss()
                    }
                }
            }
        }
    }

    /// 分类图标
    private func categoryIcon(_ category: NodeCategory) -> String {
        switch category {
        case .loader: return "arrow.down.circle"
        case .sampler: return "slider.horizontal.3"
        case .conditioning: return "wand.and.stars"
        case .encoder: return "text.alignleft"
        case .processing: return "gearshape"
        case .utility: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - 节点创建辅助

extension NodeDefinition {
    /// 根据节点定义创建NodeModel
    /// - Parameters:
    ///   - id: 节点ID
    ///   - position: 节点位置
    /// - Returns: NodeModel实例
    func createNodeModel(id: Int, position: CGPoint) -> NodeModel {
        // 创建输入插槽
        let inputSlots: [SlotModel]? = inputs.isEmpty ? nil : inputs.enumerated().map { index, slot in
            SlotModel(
                name: slot.name,
                type: slot.type,
                link: nil,
                slotIndex: index
            )
        }

        // 创建输出插槽
        let outputSlots: [SlotModel]? = outputs.isEmpty ? nil : outputs.enumerated().map { index, slot in
            SlotModel(
                name: slot.name,
                type: slot.type,
                links: [],
                slotIndex: index
            )
        }

        // 创建默认参数值
        let widgetValues: [WidgetValue]? = parameters.isEmpty ? nil : parameters.map { param in
            switch param.type {
            case .integer:
                if let defaultValue = param.defaultValue, let intValue = Int(defaultValue) {
                    return .int(intValue)
                }
                return .int(0)
            case .float:
                if let defaultValue = param.defaultValue, let doubleValue = Double(defaultValue) {
                    return .double(doubleValue)
                }
                return .double(0.0)
            case .boolean:
                if let defaultValue = param.defaultValue {
                    return .bool(defaultValue.lowercased() == "true")
                }
                return .bool(false)
            case .string, .enumeration:
                return .string(param.defaultValue ?? "")
            }
        }

        // 计算节点尺寸（根据参数数量）
        let widgetCount = parameters.count
        let baseHeight: Double = 80
        let rowHeight: Double = 22
        let height = widgetCount > 0 ? baseHeight + Double(widgetCount) * rowHeight + 20 : baseHeight
        let width: Double = 220

        return NodeModel(
            id: id,
            type: type,
            pos: [Double(position.x), Double(position.y)],
            size: [width, height],
            inputs: inputSlots,
            outputs: outputSlots,
            title: displayName,
            widgetsValues: widgetValues,
            colorHex: colorHex,
            titleColorHex: colorHex
        )
    }
}
