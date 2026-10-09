import SwiftUI

/// 节点详情检查器面板：完整展示节点信息、参数（可编辑）、插槽、原始JSON
struct NodeDetailSheet: View {
    /// 工作流数据绑定（支持参数修改后同步画布）
    @Binding var workflow: WorkflowModel
    /// 节点ID
    let nodeId: Int
    /// 关闭环境
    @Environment(\.dismiss) private var dismiss
    /// 当前选中的标签页
    @State private var selectedTab: Int = 0

    /// 当前节点
    private var node: NodeModel? {
        workflow.nodeMap[nodeId]
    }

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
                    parameterView.tag(0)
                    slotView.tag(1)
                    rawJsonView.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(node?.displayTitle ?? "节点详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - 参数页（支持编辑）

    private var parameterView: some View {
        List {
            if let node = node {
                Section("基本信息") {
                    LabeledContent("节点编号", value: "\(node.id)")
                    LabeledContent("节点类型", value: node.type)
                    if let title = node.title, !title.isEmpty {
                        LabeledContent("节点标题", value: title)
                    }
                    LabeledContent("位置", value: "(\(String(format: "%.0f", node.position.x)), \(String(format: "%.0f", node.position.y)))")
                }

                Section("控件参数（可编辑）") {
                    if let widgets = node.widgetsValues, !widgets.isEmpty {
                        ForEach(Array(widgets.enumerated()), id: \.offset) { index, widget in
                            let paramName = index < node.widgetNames.count ? node.widgetNames[index] : "参数\(index + 1)"
                            editableWidgetRow(paramName: paramName, index: index, widget: widget)
                        }
                    } else {
                        Text("无控件参数").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    /// 可编辑的参数行
    @ViewBuilder
    private func editableWidgetRow(paramName: String, index: Int, widget: WidgetValue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(paramName)
                .font(.subheadline)
                .foregroundColor(.secondary)

            switch widget.widgetKind {
            case .toggle:
                Toggle(isOn: Binding(
                    get: { widget.boolValue },
                    set: { newValue in updateWidget(index: index, value: .bool(newValue)) }
                )) {
                    Text(widget.boolValue ? "开启" : "关闭")
                        .font(.body)
                }

            case .number:
                HStack {
                    TextField("数值", text: Binding(
                        get: { widget.displayString },
                        set: { newValue in
                            if let doubleValue = Double(newValue) {
                                updateWidget(index: index, value: .double(doubleValue))
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 120)
                    Spacer()
                    Text("数值").font(.caption).foregroundColor(.secondary)
                }

            case .text:
                TextField("文本", text: Binding(
                    get: { widget.displayString },
                    set: { newValue in updateWidget(index: index, value: .string(newValue)) }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }

    /// 更新指定索引的控件值（确保值类型正确写回）
    private func updateWidget(index: Int, value: WidgetValue) {
        guard let nodeIndex = workflow.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        var node = workflow.nodes[nodeIndex]
        guard var widgets = node.widgetsValues, index < widgets.count else { return }
        widgets[index] = value
        node.widgetsValues = widgets
        workflow.nodes[nodeIndex] = node
    }

    // MARK: - 插槽页

    private var slotView: some View {
        List {
            if let node = node {
                Section("输入插槽 (\(node.inputs?.count ?? 0))") {
                    if let inputs = node.inputs, !inputs.isEmpty {
                        ForEach(Array(inputs.enumerated()), id: \.offset) { index, slot in
                            slotRow(slot: slot, index: index, isInput: true)
                        }
                    } else {
                        Text("无输入插槽").foregroundColor(.secondary)
                    }
                }

                Section("输出插槽 (\(node.outputs?.count ?? 0))") {
                    if let outputs = node.outputs, !outputs.isEmpty {
                        ForEach(Array(outputs.enumerated()), id: \.offset) { index, slot in
                            slotRow(slot: slot, index: index, isInput: false)
                        }
                    } else {
                        Text("无输出插槽").foregroundColor(.secondary)
                    }
                }

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
            if let node = node {
                let upstream = workflow.links.filter { $0.targetId == node.id }
                let downstream = workflow.links.filter { $0.sourceId == node.id }

                if !upstream.isEmpty {
                    Text("上游节点 (\(upstream.count))").font(.headline)
                    ForEach(upstream) { link in
                        if let src = workflow.nodeMap[link.sourceId] {
                            HStack {
                                Image(systemName: "arrow.right").foregroundColor(.blue)
                                Text("#\(src.id) \(src.displayTitle)")
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !downstream.isEmpty {
                    Text("下游节点 (\(downstream.count))").font(.headline)
                    ForEach(downstream) { link in
                        if let tgt = workflow.nodeMap[link.targetId] {
                            HStack {
                                Image(systemName: "arrow.right").foregroundColor(.orange)
                                Text("#\(tgt.id) \(tgt.displayTitle)")
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if upstream.isEmpty && downstream.isEmpty {
                    Text("该节点无连接").foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 原始JSON页

    private var rawJsonView: some View {
        ScrollView {
            if let node = node, let jsonString = nodeToJsonString(node: node) {
                Text(jsonString)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text("无法生成 JSON").foregroundColor(.secondary).padding()
            }
        }
    }

    private func nodeToJsonString(node: NodeModel) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(node) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
