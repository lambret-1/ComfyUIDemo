import SwiftUI

/// 节点详情检查器面板：完整展示节点信息、参数、原始JSON
struct NodeDetailSheet: View {
    /// 节点数据
    let node: NodeModel
    /// 工作流数据（用于查找上下游节点）
    let workflow: WorkflowModel?
    /// 关闭环境
    @Environment(\.dismiss) private var dismiss
    /// 当前选中的标签页
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标签切换
                Picker("详情视图", selection: $selectedTab) {
                    Text("参数").tag(0)
                    Text("插槽").tag(1)
                    Text("原始JSON").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    // 参数页
                    parameterView
                        .tag(0)
                    // 插槽页
                    slotView
                        .tag(1)
                    // 原始JSON页
                    rawJsonView
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(node.displayTitle)
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

    // MARK: - 参数页

    private var parameterView: some View {
        List {
            Section("基本信息") {
                LabeledContent("节点编号", value: "\(node.id)")
                LabeledContent("节点类型", value: node.type)
                if let title = node.title, !title.isEmpty {
                    LabeledContent("节点标题", value: title)
                }
                LabeledContent("位置", value: "(\(String(format: "%.0f", node.position.x)), \(String(format: "%.0f", node.position.y)))")
                LabeledContent("尺寸", value: "\(String(format: "%.0f", node.nodeSize.width)) × \(String(format: "%.0f", node.nodeSize.height))")
            }

            Section("控件参数 (\(node.widgetsValues?.count ?? 0))") {
                if let widgets = node.widgetsValues, !widgets.isEmpty {
                    ForEach(Array(widgets.enumerated()), id: \.offset) { index, widget in
                        HStack {
                            Text("[\(index)]")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(widget.displayString)
                                    .font(.body)
                                Text(widgetKindLabel(widget.widgetKind))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                } else {
                    Text("无控件参数")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 插槽页

    private var slotView: some View {
        List {
            Section("输入插槽 (\(node.inputs?.count ?? 0))") {
                if let inputs = node.inputs, !inputs.isEmpty {
                    ForEach(Array(inputs.enumerated()), id: \.offset) { index, slot in
                        slotRow(slot: slot, index: index, isInput: true)
                    }
                } else {
                    Text("无输入插槽")
                        .foregroundColor(.secondary)
                }
            }

            Section("输出插槽 (\(node.outputs?.count ?? 0))") {
                if let outputs = node.outputs, !outputs.isEmpty {
                    ForEach(Array(outputs.enumerated()), id: \.offset) { index, slot in
                        slotRow(slot: slot, index: index, isInput: false)
                    }
                } else {
                    Text("无输出插槽")
                        .foregroundColor(.secondary)
                }
            }

            if workflow != nil {
                Section("连接关系") {
                    connectionInfo
                }
            }
        }
    }

    private func slotRow(slot: SlotModel, index: Int, isInput: Bool) -> some View {
        HStack {
            Circle()
                .fill(SlotTypeColor.color(for: slot.type))
                .frame(width: 10, height: 10)
            Text("[\(index)] \(slot.name ?? "未命名")")
            Spacer()
            Text(slot.type ?? "未知")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    private var connectionInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let workflow = workflow {
                let upstream = workflow.links.filter { $0.targetId == node.id }
                let downstream = workflow.links.filter { $0.sourceId == node.id }

                if !upstream.isEmpty {
                    Text("上游节点 (\(upstream.count))")
                        .font(.headline)
                    ForEach(upstream) { link in
                        if let src = workflow.nodeMap[link.sourceId] {
                            HStack {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.blue)
                                Text("#\(src.id) \(src.displayTitle)")
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !downstream.isEmpty {
                    Text("下游节点 (\(downstream.count))")
                        .font(.headline)
                    ForEach(downstream) { link in
                        if let tgt = workflow.nodeMap[link.targetId] {
                            HStack {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.orange)
                                Text("#\(tgt.id) \(tgt.displayTitle)")
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if upstream.isEmpty && downstream.isEmpty {
                    Text("该节点无连接")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 原始JSON页

    private var rawJsonView: some View {
        ScrollView {
            if let jsonString = nodeToJsonString() {
                Text(jsonString)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text("无法生成 JSON")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    private func nodeToJsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(node) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 辅助

    private func widgetKindLabel(_ kind: WidgetKind) -> String {
        switch kind {
        case .text: return "文本"
        case .number: return "数值"
        case .toggle: return "开关"
        }
    }
}
