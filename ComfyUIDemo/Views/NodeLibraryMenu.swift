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
        let all = Array(NodeDatabase.allNodes.values)
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
                            Image(systemName: category.iconName)
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
}
