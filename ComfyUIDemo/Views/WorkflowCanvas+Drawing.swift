import SwiftUI

// MARK: - 画布绘制模块

extension WorkflowCanvasView {

    // MARK: - 分组绘制

    /// 绘制分组背景框与标题（最底层，ComfyUI风格）
    func drawGroups(context: GraphicsContext) {
        let titleFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        for group in workflow.groups {
            let rect = group.frame
            guard rect.width > 0, rect.height > 0 else { continue }

            let shape = RoundedRectangle(cornerRadius: 12)
            context.fill(shape.path(in: rect), with: .color(group.groupColor))
            context.stroke(shape.path(in: rect), with: .color(group.borderColor), lineWidth: 2)

            let titleBgRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: 28
            )
            context.fill(Path(titleBgRect), with: .color(group.borderColor.opacity(0.25)))

            // 高性能：直接用 NSAttributedString 绘制分组标题
            let titleTextRect = CGRect(
                x: rect.minX + 14,
                y: rect.minY + 4,
                width: rect.width - 28,
                height: 20
            )
            drawText(group.title, in: titleTextRect,
                     font: titleFont, color: UIColor(group.borderColor),
                     context: context)
        }
    }

    // MARK: - 连线绘制

    /// 绘制所有节点间的贝塞尔连线
    func drawLinks(context: GraphicsContext) {
        for link in workflow.links {
            guard let sourceNode = workflow.nodeMap[link.sourceId],
                  let targetNode = workflow.nodeMap[link.targetId] else {
                continue
            }

            // 使用渲染缓存计算插槽位置（含拖动偏移）
            let sourcePoint = cachedSlotPosition(
                node: sourceNode, slotIndex: link.sourceSlot, isOutput: true, context: context)
            let targetPoint = cachedSlotPosition(
                node: targetNode, slotIndex: link.targetSlot, isOutput: false, context: context)

            let path = bezierLinkPath(from: sourcePoint, to: targetPoint)
            let sourceSlotType = sourceNode.outputs?[safe: link.sourceSlot]?.type
            let linkColor = SlotTypeColor.color(for: sourceSlotType ?? link.linkType)
            context.stroke(path, with: .color(linkColor), lineWidth: 2.5)
        }
    }

    /// 使用缓存的插槽位置（含拖动偏移）
    func cachedSlotPosition(node: NodeModel, slotIndex: Int, isOutput: Bool, context: GraphicsContext) -> CGPoint {
        let effectivePos = effectivePosition(for: node)
        guard let render = renderCache[node.id] else {
            // 缓存未命中时降级到原计算方法
            return getSlotPosition(node: node, slotIndex: slotIndex, isOutput: isOutput)
        }
        if isOutput {
            guard slotIndex < render.outputSlotYOffsets.count else {
                return CGPoint(x: effectivePos.x + render.nodeSize.width, y: effectivePos.y)
            }
            return CGPoint(x: effectivePos.x + render.nodeSize.width,
                           y: effectivePos.y + render.outputSlotYOffsets[slotIndex])
        } else {
            guard slotIndex < render.inputSlotYOffsets.count else {
                return CGPoint(x: effectivePos.x, y: effectivePos.y)
            }
            return CGPoint(x: effectivePos.x,
                           y: effectivePos.y + render.inputSlotYOffsets[slotIndex])
        }
    }

    /// 生成两点间的三次贝塞尔曲线路径
    func bezierLinkPath(from: CGPoint, to: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            let dx = to.x - from.x
            let offset = min(150.0, max(30.0, abs(dx) * 0.5))
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + offset, y: from.y),
                control2: CGPoint(x: to.x - offset, y: to.y)
            )
        }
    }

    // MARK: - 节点绘制

    /// 绘制所有节点
    func drawNodes(context: GraphicsContext, highlightedId: Int? = nil) {
        let titleFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let typeFont = UIFont.systemFont(ofSize: 8)

        for node in workflow.nodes {
            let effectivePos = effectivePosition(for: node)
            let render = renderCache[node.id]
            let nodeSize = render?.nodeSize ?? node.nodeSize
            let rect = CGRect(origin: effectivePos, size: nodeSize)
            let shape = RoundedRectangle(cornerRadius: 8)

            if highlightedId == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -6, dy: -6)), with: .color(.yellow.opacity(0.4)))
            }

            if draggingNodeId == node.id {
                context.fill(shape.path(in: rect.insetBy(dx: -4, dy: -4)), with: .color(.black.opacity(0.2)))
            }

            context.fill(shape.path(in: rect), with: .color(node.bodyColor))
            context.stroke(shape.path(in: rect), with: .color(node.headerColor), lineWidth: 2)

            let headerHeight = render?.headerHeight ?? min(30, rect.height * 0.4)
            let headerRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: headerHeight
            )
            context.fill(shape.path(in: headerRect), with: .color(node.headerColor))

            // 节点标题（始终绘制，节点可识别）——高性能 NSAttributedString
            let titleText = render?.displayTitle ?? node.displayTitle
            drawText(titleText, in: headerRect.insetBy(dx: 8, dy: 6),
                     font: titleFont, color: .white, context: context)

            // 右上角双圈圆点（详情页入口）——与 handleTap 的命中测试保持一致：18 + 6
            let infoButtonSize: CGFloat = 18
            let infoButtonX = rect.maxX - infoButtonSize - 6
            let infoButtonY = headerRect.midY - infoButtonSize / 2
            let infoButtonRect = CGRect(x: infoButtonX, y: infoButtonY, width: infoButtonSize, height: infoButtonSize)
            context.stroke(Path(ellipseIn: infoButtonRect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            let innerInset: CGFloat = 4
            context.stroke(Path(ellipseIn: infoButtonRect.insetBy(dx: innerInset, dy: innerInset)), with: .color(.white.opacity(0.9)), lineWidth: 1.5)

            // 控件区域
            let widgetTop = headerRect.maxY + 6
            let widgetBottom = rect.maxY - 20
            let baseLeftInset: CGFloat = 75
            let baseRightInset: CGFloat = 85
            let minWidgetWidth: CGFloat = 60
            var leftInset = baseLeftInset
            var rightInset = baseRightInset
            if rect.width - leftInset - rightInset < minWidgetWidth {
                let available = rect.width - minWidgetWidth
                let totalInset = baseLeftInset + baseRightInset
                let scale = min(1.0, available / totalInset)
                leftInset = baseLeftInset * scale
                rightInset = baseRightInset * scale
            }
            let widgetX = rect.minX + leftInset
            let widgetWidth = max(40, rect.width - leftInset - rightInset)
            if let widgets = node.widgetsValues, !widgets.isEmpty, widgetWidth > 40 {
                drawWidgets(
                    context: context,
                    widgets: widgets,
                    render: render,
                    in: CGRect(x: widgetX, y: widgetTop, width: widgetWidth, height: widgetBottom - widgetTop)
                )
            }

            // 节点类型标签：交互时跳过（降级渲染）
            if !isInteracting {
                let typeLabelHeight: CGFloat = 16
                let typeRect = CGRect(
                    x: rect.minX,
                    y: rect.maxY - typeLabelHeight,
                    width: rect.width,
                    height: typeLabelHeight
                )
                let typeLabel = render?.typeLabel ?? node.type
                drawText(typeLabel, in: typeRect.insetBy(dx: 8, dy: 2),
                         font: typeFont, color: .secondaryLabel, context: context)
            }

            // 插槽绘制（圆点始终绘制，名称交互时跳过）
            drawSlots(context: context, node: node, render: render)
        }
    }

    // MARK: - 控件绘制

    /// 绘制节点内部控件
    func drawWidgets(context: GraphicsContext, widgets: [WidgetValue],
                     render: NodeRenderData?, in rect: CGRect) {
        let controlHeight: CGFloat = 16
        let rowSpacing: CGFloat = 6
        let labelWidth: CGFloat = 48
        let valueFont = UIFont.systemFont(ofSize: 8)
        let numFont = UIFont.systemFont(ofSize: 9)
        var currentY = rect.minY

        for (index, widget) in widgets.enumerated() {
            let totalRowHeight = controlHeight + rowSpacing

            // 控件标签：交互时跳过（降级渲染）
            if !isInteracting {
                let labelCenterY = currentY + controlHeight / 2
                let displayName = render?.widgetLabels[safe: index] ?? ""
                if !displayName.isEmpty {
                    drawTextAtPoint(displayName,
                                    at: CGPoint(x: rect.minX + labelWidth - 2, y: labelCenterY),
                                    font: UIFont.systemFont(ofSize: 8),
                                    color: .secondaryLabel,
                                    anchor: .trailing, context: context)
                }
            }

            let controlX = rect.minX + labelWidth + 4
            let controlWidth = rect.width - labelWidth - 4
            let controlY = currentY

            switch widget.widgetKind {
            case .toggle:
                let isOn = widget.boolValue
                let toggleRect = CGRect(x: controlX, y: controlY + 1, width: 28, height: 14)
                let toggleShape = RoundedRectangle(cornerRadius: 7)
                context.fill(toggleShape.path(in: toggleRect), with: .color(isOn ? .green : .gray.opacity(0.4)))
                let knobX = isOn ? toggleRect.maxX - 11 : toggleRect.minX + 2
                let knobRect = CGRect(x: knobX, y: toggleRect.minY + 1, width: 11, height: 12)
                context.fill(Path(ellipseIn: knobRect), with: .color(.white))
                // 开关状态文字：交互时跳过
                if !isInteracting {
                    drawTextAtPoint(isOn ? "开" : "关",
                                    at: CGPoint(x: toggleRect.maxX + 4, y: controlY + 8),
                                    font: UIFont.systemFont(ofSize: 8),
                                    color: .secondaryLabel,
                                    anchor: .leading, context: context)
                }

            case .number:
                let numWidth: CGFloat = 48
                let numRect = CGRect(x: controlX, y: controlY, width: numWidth, height: controlHeight)
                let numShape = RoundedRectangle(cornerRadius: 4)
                context.fill(numShape.path(in: numRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(numShape.path(in: numRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                // 数值文本
                drawText(widget.displayString, in: numRect.insetBy(dx: 4, dy: 1),
                         font: numFont, color: .label, context: context)

                let sliderX = numRect.maxX + 6
                let sliderWidth = max(0, controlWidth - numWidth - 6)
                if sliderWidth > 20 {
                    let sliderRect = CGRect(x: sliderX, y: controlY + 6, width: sliderWidth, height: 4)
                    context.fill(Path(roundedRect: sliderRect, cornerSize: CGSize(width: 2, height: 2)),
                               with: .color(.gray.opacity(0.25)))
                    let numericValue: Double
                    switch widget {
                    case .int(let v): numericValue = Double(v)
                    case .double(let v): numericValue = v
                    default: numericValue = 0
                    }
                    let ratio = max(0, min(1, numericValue / 100))
                    let knobX = sliderX + sliderWidth * ratio
                    let knobRect = CGRect(x: knobX - 4, y: controlY + 3, width: 8, height: 10)
                    context.fill(Path(ellipseIn: knobRect), with: .color(.blue))
                }

            case .text:
                let text = widget.displayString
                let isShortEnum = text.count <= 15 && !text.contains(" ") && !text.contains("\n") && controlWidth > 60
                let textRect = CGRect(x: controlX, y: controlY, width: controlWidth, height: controlHeight)
                let textShape = RoundedRectangle(cornerRadius: 4)
                context.fill(textShape.path(in: textRect), with: .color(Color(.tertiarySystemBackground)))
                context.stroke(textShape.path(in: textRect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)

                let textMaxWidth = isShortEnum ? controlWidth - 16 : controlWidth - 8
                let displayText = truncatedText(text, font: valueFont, maxWidth: textMaxWidth)
                drawText(displayText, in: textRect.insetBy(dx: 4, dy: 2),
                         font: valueFont, color: .label, context: context)

                if isShortEnum {
                    let arrowX = textRect.maxX - 12
                    let arrowPath = Path { p in
                        p.move(to: CGPoint(x: arrowX, y: controlY + 5))
                        p.addLine(to: CGPoint(x: arrowX + 4, y: controlY + 9))
                        p.addLine(to: CGPoint(x: arrowX + 8, y: controlY + 5))
                    }
                    context.stroke(arrowPath, with: .color(.gray), lineWidth: 1)
                }
            }

            currentY += totalRowHeight
        }
    }

    // MARK: - 插槽绘制与定位

    /// 绘制节点的输入/输出插槽圆点及名称标签（交互时跳过名称）
    func drawSlots(context: GraphicsContext, node: NodeModel, render: NodeRenderData?) {
        let dotSize: CGFloat = 10
        let effectivePos = effectivePosition(for: node)
        let nodeSize = render?.nodeSize ?? node.nodeSize

        if let outputs = node.outputs {
            for (index, slot) in outputs.enumerated() {
                // 使用缓存的Y偏移计算插槽位置
                let yOffset = render?.outputSlotYOffsets[safe: index] ?? {
                    let headerHeight = render?.headerHeight ?? min(30, nodeSize.height * 0.4)
                    return headerHeight + 8 + CGFloat(index) * 20
                }()
                let point = CGPoint(x: effectivePos.x + nodeSize.width, y: effectivePos.y + yOffset)

                let dotRect = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let slotColor = SlotTypeColor.color(for: slot.type)
                context.fill(Path(ellipseIn: dotRect), with: .color(slotColor))
                context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)

                // 插槽名称：交互时跳过
                if !isInteracting, let slotName = slot.name, !slotName.isEmpty {
                    let displayName = render?.outputSlotNames[safe: index] ?? {
                        let localized = SlotLocalization.localized(for: slotName)
                        return truncatedText(localized, font: UIFont.systemFont(ofSize: 9), maxWidth: 70)
                    }()
                    if !displayName.isEmpty {
                        let labelPoint = CGPoint(x: point.x - dotSize / 2 - 5, y: point.y)
                        drawTextAtPoint(displayName, at: labelPoint,
                                        font: UIFont.systemFont(ofSize: 9),
                                        color: .secondaryLabel,
                                        anchor: .trailing, context: context)
                    }
                }
            }
        }

        if let inputs = node.inputs {
            for (index, slot) in inputs.enumerated() {
                let yOffset = render?.inputSlotYOffsets[safe: index] ?? {
                    let headerHeight = render?.headerHeight ?? min(30, nodeSize.height * 0.4)
                    return headerHeight + 8 + CGFloat(index) * 20
                }()
                let point = CGPoint(x: effectivePos.x, y: effectivePos.y + yOffset)

                let dotRect = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let slotColor = SlotTypeColor.color(for: slot.type)
                context.fill(Path(ellipseIn: dotRect), with: .color(slotColor))
                context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)

                // 插槽名称：交互时跳过
                if !isInteracting, let slotName = slot.name, !slotName.isEmpty {
                    let displayName = render?.inputSlotNames[safe: index] ?? {
                        let localized = SlotLocalization.localized(for: slotName)
                        return truncatedText(localized, font: UIFont.systemFont(ofSize: 9), maxWidth: 60)
                    }()
                    if !displayName.isEmpty {
                        let labelPoint = CGPoint(x: point.x + dotSize / 2 + 5, y: point.y)
                        drawTextAtPoint(displayName, at: labelPoint,
                                        font: UIFont.systemFont(ofSize: 9),
                                        color: .secondaryLabel,
                                        anchor: .leading, context: context)
                    }
                }
            }
        }
    }

    /// 文本截断（二分查找版，O(log n)次尺寸计算，解决超长文本O(n²)卡死问题）
    func truncatedText(_ text: String, font: UIFont, maxWidth: CGFloat) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        // 整个文本能放下直接返回
        if (text as NSString).size(withAttributes: attributes).width <= maxWidth {
            return text
        }
        // 超长文本预处理硬上限：先截取前500字，避免二分范围过大
        let maxPreprocessLength = 500
        let searchText = text.count > maxPreprocessLength
            ? String(text.prefix(maxPreprocessLength))
            : text

        // 二分查找最大可显示字符数：prefix(k)+"…" 宽度 <= maxWidth
        var low = 0
        var high = searchText.count
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(searchText.prefix(mid)) + "…"
            let width = (candidate as NSString).size(withAttributes: attributes).width
            if width <= maxWidth {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best > 0 ? String(searchText.prefix(best)) + "…" : "…"
    }

    /// 计算插槽在画布中的坐标（降级方案：缓存未命中时使用）
    func getSlotPosition(node: NodeModel, slotIndex: Int, isOutput: Bool) -> CGPoint {
        let rect = CGRect(origin: node.position, size: node.nodeSize)
        let headerHeight = min(30, rect.height * 0.4)
        let slotAreaTop = rect.minY + headerHeight + 8
        let slotGap: CGFloat = 20
        let y = slotAreaTop + CGFloat(slotIndex) * slotGap

        if isOutput {
            return CGPoint(x: rect.maxX, y: y)
        } else {
            return CGPoint(x: rect.minX, y: y)
        }
    }

    // MARK: - 背景网格

    func drawGrid(context: GraphicsContext, viewSize: CGSize) {
        let gridStep: CGFloat = 40
        var path = Path()
        for x in stride(from: 0, through: viewSize.width, by: gridStep) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: viewSize.height))
        }
        for y in stride(from: 0, through: viewSize.height, by: gridStep) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: viewSize.width, y: y))
        }
        context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
    }
}
