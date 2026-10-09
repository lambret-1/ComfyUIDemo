import SwiftUI

/// 独立节点视图：使用SwiftUI原生视图渲染节点，支持自由拖动和参数直接编辑
/// 替代原Canvas绘制节点的方式，解决控件漂移、重影、手势冲突等问题
struct NodeView: View {
    // MARK: - 输入参数

    /// 节点数据
    let node: NodeModel
    /// 是否选中（蓝色发光边框）
    let isSelected: Bool
    /// 视图模型（用于参数编辑）
    @ObservedObject var viewModel: WorkflowViewModel
    /// 点击节点空白区域回调
    let onTap: () -> Void
    /// 点击右上角详情按钮回调
    let onInfo: () -> Void
    /// 节点拖动回调（屏幕坐标系位移）
    let onDrag: (CGSize) -> Void

    // MARK: - 布局常量

    private let headerHeight: CGFloat = 30
    private let rowHeight: CGFloat = 22
    private let labelWidth: CGFloat = 48
    private let baseLeftInset: CGFloat = 75
    private let baseRightInset: CGFloat = 85
    private let minWidgetWidth: CGFloat = 60

    // MARK: - 计算属性

    /// 动态边距（与Canvas绘制一致）
    private var leftInset: CGFloat {
        let width = node.nodeSize.width
        if width - baseLeftInset - baseRightInset < minWidgetWidth {
            let available = width - minWidgetWidth
            let totalInset = baseLeftInset + baseRightInset
            let scale = min(1.0, available / totalInset)
            return baseLeftInset * scale
        }
        return baseLeftInset
    }

    private var rightInset: CGFloat {
        let width = node.nodeSize.width
        if width - baseLeftInset - baseRightInset < minWidgetWidth {
            let available = width - minWidgetWidth
            let totalInset = baseLeftInset + baseRightInset
            let scale = min(1.0, available / totalInset)
            return baseRightInset * scale
        }
        return baseRightInset
    }

    private var widgetWidth: CGFloat {
        node.nodeSize.width - leftInset - rightInset
    }

    // MARK: - body

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 节点主体
            VStack(alignment: .leading, spacing: 0) {
                // 标题栏
                headerView
                // 内容区（插槽+控件）
                contentView
            }
            .frame(width: node.nodeSize.width, height: node.nodeSize.height, alignment: .topLeading)
            .background(node.bodyColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(node.headerColor, lineWidth: 2)
            )
            // 选中边框（overlay不挤压布局）
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2.5)
                        .padding(-2)
                }
            }
            // 点击空白区域选中节点
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            // 节点自由拖动（高优先级，优先于画布平移）
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        onDrag(value.translation)
                    }
            )
        }
        .frame(width: node.nodeSize.width, height: node.nodeSize.height)
    }

    // MARK: - 标题栏

    private var headerView: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(node.headerColor)
                .frame(height: headerHeight)

            HStack(spacing: 0) {
                Text(node.displayTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .padding(.trailing, 30)

                Spacer()

                // 右上角双圈圆点（详情页入口）
                Button(action: onInfo) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
            }
        }
        .frame(height: headerHeight)
    }

    // MARK: - 内容区（插槽+控件）

    private var contentView: some View {
        ZStack(alignment: .topLeading) {
            // 左侧输入插槽
            inputSlotsView
            // 右侧输出插槽
            outputSlotsView
            // 中间控件区域
            if widgetWidth > 40 {
                widgetControlsView
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)
                    .padding(.top, headerHeight + 6)
            }
        }
    }

    // MARK: - 输入插槽

    private var inputSlotsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let inputs = node.inputs, !inputs.isEmpty {
                ForEach(Array(inputs.enumerated()), id: \.offset) { index, slot in
                    let slotY = headerHeight + 6 + CGFloat(index) * rowHeight
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SlotTypeColor.color(for: slot.type))
                            .frame(width: 8, height: 8)
                        Text(SlotLocalization.localized(for: slot.name ?? ""))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                            .lineLimit(1)
                    }
                    .frame(height: 16, alignment: .center)
                    .offset(y: slotY - (headerHeight + 6))
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - 输出插槽

    private var outputSlotsView: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let outputs = node.outputs, !outputs.isEmpty {
                ForEach(Array(outputs.enumerated()), id: \.offset) { index, slot in
                    let slotY = headerHeight + 6 + CGFloat(index) * rowHeight
                    HStack(spacing: 4) {
                        Text(SlotLocalization.localized(for: slot.name ?? ""))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                            .lineLimit(1)
                        Circle()
                            .fill(SlotTypeColor.color(for: slot.type))
                            .frame(width: 8, height: 8)
                    }
                    .frame(height: 16, alignment: .center)
                    .offset(y: slotY - (headerHeight + 6))
                }
            }
        }
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - 控件区域

    private var widgetControlsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let widgets = node.widgetsValues, !widgets.isEmpty {
                ForEach(Array(widgets.enumerated()), id: \.offset) { index, widget in
                    let controlWidth = widgetWidth - labelWidth - 4
                    let rawName = index < node.widgetNames.count ? node.widgetNames[index] : "参数\(index + 1)"
                    let paramName = SlotLocalization.localized(for: rawName)

                    HStack(spacing: 0) {
                        // 参数名标签（右对齐）
                        Text(paramName)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(width: labelWidth - 2, height: 16, alignment: .trailing)
                            .lineLimit(1)

                        Spacer().frame(width: 4)

                        // 控件
                        widgetControl(widget: widget, index: index, controlWidth: controlWidth)
                    }
                    .frame(width: widgetWidth, height: rowHeight, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 单个控件

    @ViewBuilder
    private func widgetControl(widget: WidgetValue, index: Int, controlWidth: CGFloat) -> some View {
        switch widget.widgetKind {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { viewModel.currentWidgetValue(nodeID: node.id, index: index)?.boolValue ?? false },
                set: { newValue in
                    viewModel.updateWidget(nodeID: node.id, index: index, value: .bool(newValue))
                }
            ))
            .labelsHidden()
            .frame(width: 28, height: 16)

        case .number:
            HStack(spacing: 6) {
                TextField("", text: Binding(
                    get: { viewModel.currentWidgetValue(nodeID: node.id, index: index)?.displayString ?? "" },
                    set: { newValue in
                        let original = viewModel.currentWidgetValue(nodeID: node.id, index: index)
                        if case .int = original {
                            if let intValue = Int(newValue) {
                                viewModel.updateWidget(nodeID: node.id, index: index, value: .int(intValue))
                            }
                        } else {
                            if let doubleValue = Double(newValue) {
                                viewModel.updateWidget(nodeID: node.id, index: index, value: .double(doubleValue))
                            }
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 9))
                .keyboardType(.decimalPad)
                .frame(width: 48, height: 16)
                .multilineTextAlignment(.center)

                if controlWidth > 74 {
                    Slider(value: Binding(
                        get: {
                            if let v = viewModel.currentWidgetValue(nodeID: node.id, index: index) {
                                switch v {
                                case .int(let val): return Double(val)
                                case .double(let val): return val
                                default: return 0
                                }
                            }
                            return 0
                        },
                        set: { newValue in
                            let original = viewModel.currentWidgetValue(nodeID: node.id, index: index)
                            if case .int = original {
                                viewModel.updateWidget(nodeID: node.id, index: index, value: .int(Int(newValue)))
                            } else {
                                viewModel.updateWidget(nodeID: node.id, index: index, value: .double(newValue))
                            }
                        }
                    ), in: 0...100)
                    .frame(width: controlWidth - 54, height: 16)
                }
            }

        case .text:
            TextField("", text: Binding(
                get: { viewModel.currentWidgetValue(nodeID: node.id, index: index)?.displayString ?? "" },
                set: { newValue in
                    viewModel.updateWidget(nodeID: node.id, index: index, value: .string(newValue))
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 8))
            .frame(width: controlWidth, height: 16)
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }
}
