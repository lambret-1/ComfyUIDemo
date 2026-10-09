import SwiftUI

/// 节点搜索页面：输入关键词搜索节点，点击后定位到画布
struct NodeSearchPage: View {
    /// 工作流数据
    let workflow: WorkflowModel
    /// 选中节点回调
    let onSelect: (Int) -> Void
    /// 搜索关键词
    @State private var searchText: String = ""
    /// 环境关闭
    @Environment(\.dismiss) private var dismiss

    /// 过滤后的节点列表
    private var filteredNodes: [NodeModel] {
        guard !searchText.isEmpty else { return workflow.nodes }
        let lower = searchText.lowercased()
        return workflow.nodes.filter { node in
            node.type.lowercased().contains(lower) ||
            node.displayTitle.lowercased().contains(lower) ||
            "\(node.id)".contains(lower)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索节点名称或编号", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding()

                // 搜索结果列表
                List {
                    ForEach(filteredNodes) { node in
                        Button {
                            onSelect(node.id)
                        } label: {
                            HStack(spacing: 12) {
                                // 节点颜色标识
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(node.headerColor)
                                    .frame(width: 4, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(node.displayTitle)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text("#\(node.id) · \(node.type)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "location.north.line")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("搜索节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                }
            }
        }
    }
}
