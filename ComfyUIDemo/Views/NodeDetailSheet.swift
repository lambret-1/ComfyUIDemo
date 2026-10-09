import SwiftUI

/// 节点详情弹窗：展示节点的完整信息
struct NodeDetailSheet: View {
    /// 节点数据
    let node: NodeModel
    /// 关闭环境
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    LabeledContent("节点编号", value: "\(node.id)")
                    LabeledContent("节点类型", value: node.type)
                    if let title = node.title, !title.isEmpty {
                        LabeledContent("节点标题", value: title)
                    }
                    LabeledContent("位置 X", value: String(format: "%.1f", node.position.x))
                    LabeledContent("位置 Y", value: String(format: "%.1f", node.position.y))
                    LabeledContent("宽度", value: String(format: "%.1f", node.nodeSize.width))
                    LabeledContent("高度", value: String(format: "%.1f", node.nodeSize.height))
                }

                Section("输入插槽 (\(node.inputs?.count ?? 0))") {
                    if let inputs = node.inputs, !inputs.isEmpty {
                        ForEach(Array(inputs.enumerated()), id: \.offset) { index, slot in
                            HStack {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                                Text("[\(index)] \(slot.name ?? "未命名")")
                                Spacer()
                                Text(slot.type ?? "未知")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Text("无输入插槽")
                            .foregroundColor(.secondary)
                    }
                }

                Section("输出插槽 (\(node.outputs?.count ?? 0))") {
                    if let outputs = node.outputs, !outputs.isEmpty {
                        ForEach(Array(outputs.enumerated()), id: \.offset) { index, slot in
                            HStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("[\(index)] \(slot.name ?? "未命名")")
                                Spacer()
                                Text(slot.type ?? "未知")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Text("无输出插槽")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("节点详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
