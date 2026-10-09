import Foundation
import SwiftUI

// MARK: - 工作流根模型

/// 工作流根模型，对应 ComfyUI 导出的 workflow.json 顶层结构
struct WorkflowModel: Codable {
    /// 节点列表
    var nodes: [NodeModel]
    /// 连线列表（ComfyUI 原生为嵌套数组，已转换为结构化模型）
    var links: [LinkModel]
    /// 分组列表
    var groups: [GroupModel]

    /// 以节点编号为键的快速查找表
    var nodeMap: [Int: NodeModel] {
        nodes.reduce(into: [:]) { map, node in
            map[node.id] = node
        }
    }

    enum CodingKeys: String, CodingKey {
        case nodes, links, groups
    }

    /// 成员初始化器（用于创建空白工作流）
    init(nodes: [NodeModel] = [], links: [LinkModel] = [], groups: [GroupModel] = []) {
        self.nodes = nodes
        self.links = links
        self.groups = groups
    }

    /// 自定义解码：兼容 ComfyUI 原生 links 为嵌套数组的格式，容错解析
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 节点容错解析：单个节点解析失败不影响整体
        if let nodeContainers = try? container.decode([SafeDecodable<NodeModel>].self, forKey: .nodes) {
            nodes = nodeContainers.compactMap { $0.value }
        } else {
            nodes = []
        }

        // ComfyUI 原生 links 是 [[link_id, source_id, source_slot, target_id, target_slot, type]]
        if let nestedLinks = try? container.decode([[RawLinkValue]].self, forKey: .links) {
            links = nestedLinks.compactMap { LinkModel(rawArray: $0) }
        } else if let objectLinks = try? container.decode([LinkModel].self, forKey: .links) {
            links = objectLinks
        } else {
            links = []
        }

        // 分组容错解析
        if let groupContainers = try? container.decode([SafeDecodable<GroupModel>].self, forKey: .groups) {
            groups = groupContainers.compactMap { $0.value }
        } else {
            groups = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(links, forKey: .links)
        try container.encode(groups, forKey: .groups)
    }
}

/// 安全解码包装器：单个元素解码失败时返回nil而不是抛出
struct SafeDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
        } catch {
            value = nil
        }
    }
}

// MARK: - 节点模型

/// 节点模型，对应 ComfyUI nodes 数组中的单个节点
struct NodeModel: Codable, Identifiable, Hashable {
    /// 节点编号
    let id: Int
    /// 节点类型名称
    let type: String
    /// 节点在画布中的位置 [x, y]
    var pos: [Double]
    /// 节点尺寸 [width, height]
    let size: [Double]
    /// 输入插槽列表
    let inputs: [SlotModel]?
    /// 输出插槽列表
    let outputs: [SlotModel]?
    /// 节点标题
    let title: String?
    /// 控件值列表（多态：字符串/数字/布尔，可编辑）
    var widgetsValues: [WidgetValue]?
    /// 节点自定义颜色（ComfyUI 中为 "#RRGGBB" 格式）
    let colorHex: String?
    /// 节点标题栏自定义颜色
    let titleColorHex: String?

    /// 计算属性：节点左上角坐标
    var position: CGPoint {
        guard pos.count >= 2 else { return .zero }
        return CGPoint(x: pos[0], y: pos[1])
    }

    /// 计算属性：节点尺寸（严格遵循JSON原始坐标比例，宽度使用原始size，高度仅在控件过多时增加）
    var nodeSize: CGSize {
        guard size.count >= 2 else { return CGSize(width: 200, height: 80) }
        // 宽度严格使用JSON原始值，保持坐标比例一致（仅设极小下限避免异常）
        let minWidth: CGFloat = 120
        let width = max(size[0], minWidth)
        let baseHeight = max(size[1], 40)
        let widgetCount = widgetsValues?.count ?? 0

        guard widgetCount > 0 else {
            return CGSize(width: width, height: baseHeight)
        }

        // 高度仅当控件数量超出原始高度时才增加，宽度保持原始值
        let headerHeight: CGFloat = 30
        let widgetTopPadding: CGFloat = 6
        let widgetBottomPadding: CGFloat = 20
        let rowHeight: CGFloat = 22
        let neededHeight = headerHeight + widgetTopPadding + CGFloat(widgetCount) * rowHeight + widgetBottomPadding
        let finalHeight = max(baseHeight, neededHeight)
        return CGSize(width: width, height: finalHeight)
    }

    /// 节点显示标题：优先 title，其次 type
    var displayTitle: String {
        title?.isEmpty == false ? title! : type
    }

    /// 控件参数名列表（严格从WidgetNameRegistry预设映射获取，绝不从inputs插槽名借用）
    /// 注意：inputs.name是插槽名（用于画端口圆点和连线），widgets_values的参数名必须由节点类型预先定义
    var widgetNames: [String] {
        let widgetCount = widgetsValues?.count ?? 0
        guard widgetCount > 0 else { return [] }

        // 1. 用节点类型的预设参数名映射（策略A：内置映射字典）
        if let presetNames = WidgetNameRegistry.names(for: type) {
            var names = [String](repeating: "", count: widgetCount)
            for i in 0..<min(presetNames.count, widgetCount) {
                names[i] = presetNames[i]
            }
            for i in 0..<widgetCount where names[i].isEmpty {
                names[i] = "参数\(i + 1)"
            }
            return names
        }

        // 2. 兜底用序号
        return (0..<widgetCount).map { "参数\($0 + 1)" }
    }

    /// 节点主体背景色（始终为白色/浅灰，colorHex仅用于标题栏，避免整个节点被颜色填充）
    var bodyColor: Color {
        Color(.secondarySystemBackground)
    }

    /// 节点标题栏背景色
    var headerColor: Color {
        if let hex = titleColorHex, let color = Color(hex: hex) {
            return color
        }
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return NodeTypeColor.color(for: type)
    }

    enum CodingKeys: String, CodingKey {
        case id, type, pos, size, inputs, outputs, title
        case widgetsValues = "widgets_values"
        case colorHex = "color"
        case titleColorHex = "title_color"
    }

    /// 成员初始化器（用于从节点库创建新节点）
    init(id: Int, type: String, pos: [Double], size: [Double],
         inputs: [SlotModel]?, outputs: [SlotModel]?, title: String?,
         widgetsValues: [WidgetValue]?, colorHex: String?, titleColorHex: String?) {
        self.id = id
        self.type = type
        self.pos = pos
        self.size = size
        self.inputs = inputs
        self.outputs = outputs
        self.title = title
        self.widgetsValues = widgetsValues
        self.colorHex = colorHex
        self.titleColorHex = titleColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 兼容 id 为字符串或整数
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
        } else if let strId = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(strId) {
            id = parsed
        } else {
            id = 0
        }
        type = (try? container.decode(String.self, forKey: .type)) ?? "Unknown"
        pos = (try? container.decode([Double].self, forKey: .pos)) ?? [0, 0]
        size = (try? container.decode([Double].self, forKey: .size)) ?? [200, 80]
        inputs = try? container.decodeIfPresent([SlotModel].self, forKey: .inputs)
        outputs = try? container.decodeIfPresent([SlotModel].self, forKey: .outputs)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        colorHex = try? container.decodeIfPresent(String.self, forKey: .colorHex)
        titleColorHex = try? container.decodeIfPresent(String.self, forKey: .titleColorHex)

        // 多态 widgets_values 解析
        if let rawWidgets = try? container.decode([RawWidgetValue].self, forKey: .widgetsValues) {
            widgetsValues = rawWidgets.map { WidgetValue(raw: $0) }
        } else {
            widgetsValues = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(pos, forKey: .pos)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(inputs, forKey: .inputs)
        try container.encodeIfPresent(outputs, forKey: .outputs)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(widgetsValues, forKey: .widgetsValues)
        try container.encodeIfPresent(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(titleColorHex, forKey: .titleColorHex)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: NodeModel, rhs: NodeModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 插槽模型

/// 插槽模型，对应节点的 inputs / outputs 数组元素
struct SlotModel: Codable, Hashable {
    /// 插槽名称
    let name: String?
    /// 插槽数据类型
    let type: String?
    /// 插槽索引
    let slotIndex: Int?
    /// 关联的连线编号列表
    let links: [Int]?
    /// 关联的控件索引（input中如有widget字段，则该input对应widgets_values中的第N个控件）
    let widgetIndex: Int?

    enum CodingKeys: String, CodingKey {
        case name, type, links, widget
        case slotIndex = "slot_index"
    }

    /// 成员初始化器（用于创建新节点时构造插槽）
    init(name: String?, type: String?, link: Int? = nil, links: [Int]? = nil, slotIndex: Int? = nil, widgetIndex: Int? = nil) {
        self.name = name
        self.type = type
        self.slotIndex = slotIndex
        self.links = links
        self.widgetIndex = widgetIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        slotIndex = try? container.decodeIfPresent(Int.self, forKey: .slotIndex)
        links = try? container.decodeIfPresent([Int].self, forKey: .links)
        // ComfyUI中widget字段是整数，指向widgets_values的索引
        widgetIndex = try? container.decodeIfPresent(Int.self, forKey: .widget)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(slotIndex, forKey: .slotIndex)
        try container.encodeIfPresent(links, forKey: .links)
        try container.encodeIfPresent(widgetIndex, forKey: .widget)
    }
}

// MARK: - 连线模型

/// 连线模型
struct LinkModel: Codable, Identifiable, Hashable {
    /// 连线编号
    let id: Int
    /// 源节点编号
    let sourceId: Int
    /// 源节点输出插槽索引
    let sourceSlot: Int
    /// 目标节点编号
    let targetId: Int
    /// 目标节点输入插槽索引
    let targetSlot: Int
    /// 连线数据类型
    let linkType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId = "source_id"
        case sourceSlot = "source_slot"
        case targetId = "target_id"
        case targetSlot = "target_slot"
        case linkType = "type"
    }

    /// 从 ComfyUI 原生嵌套数组构造
    init?(rawArray: [RawLinkValue]) {
        guard rawArray.count >= 5,
              let linkId = rawArray[0].intValue,
              let srcId = rawArray[1].intValue,
              let srcSlot = rawArray[2].intValue,
              let tgtId = rawArray[3].intValue,
              let tgtSlot = rawArray[4].intValue else {
            return nil
        }
        id = linkId
        sourceId = srcId
        sourceSlot = srcSlot
        targetId = tgtId
        targetSlot = tgtSlot
        linkType = rawArray.count >= 6 ? rawArray[5].stringValue : nil
    }

    /// 成员初始化器（用于创建新连线）
    init(id: Int, sourceId: Int, sourceSlot: Int, targetId: Int, targetSlot: Int, linkType: String? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.sourceSlot = sourceSlot
        self.targetId = targetId
        self.targetSlot = targetSlot
        self.linkType = linkType
    }
}

// MARK: - 分组模型

/// 分组边界框对象格式（兼容某些ComfyUI版本）
private struct BoundingObject: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// 分组模型，对应 ComfyUI groups 数组
struct GroupModel: Codable, Identifiable, Hashable {
    /// 分组标题
    let title: String
    /// 分组边界框 [x, y, width, height]
    let bounding: [Double]
    /// 分组颜色
    let colorHex: String?
    /// 字体大小
    let fontSize: Int?

    var id: String { title }

    /// 分组矩形
    var frame: CGRect {
        guard bounding.count >= 4 else { return .zero }
        return CGRect(
            x: bounding[0],
            y: bounding[1],
            width: bounding[2],
            height: bounding[3]
        )
    }

    /// 分组背景色（增强可见性）
    var groupColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color.opacity(0.18)
        }
        return Color.blue.opacity(0.12)
    }

    /// 分组边框色（增强可见性）
    var borderColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color.opacity(0.85)
        }
        return Color.blue.opacity(0.6)
    }

    enum CodingKeys: String, CodingKey {
        case title, bounding, color
        case fontSize = "font_size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decode(String.self, forKey: .title)) ?? "未命名分组"
        // 兼容 bounding 为数组 [x,y,w,h] 或对象 {x,y,width,height}
        if let boundingArray = try? container.decode([Double].self, forKey: .bounding) {
            bounding = boundingArray
        } else if let boundingObj = try? container.decode(BoundingObject.self, forKey: .bounding) {
            bounding = [boundingObj.x, boundingObj.y, boundingObj.width, boundingObj.height]
        } else {
            bounding = [0, 0, 200, 200]
        }
        colorHex = try? container.decodeIfPresent(String.self, forKey: .color)
        fontSize = try? container.decodeIfPresent(Int.self, forKey: .fontSize)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(bounding, forKey: .bounding)
        try container.encodeIfPresent(colorHex, forKey: .color)
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
    }
}

// MARK: - 控件值（多态）

/// 控件值类型枚举
enum WidgetValue: Hashable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// 显示用字符串
    var displayString: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return "\(v)"
        case .double(let v):
            // 整数形式的浮点数去掉小数点
            if v.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(v))"
            }
            return String(format: "%.4g", v)
        case .bool(let v): return v ? "开" : "关"
        case .null: return "空"
        }
    }

    /// 控件类型推断
    var widgetKind: WidgetKind {
        switch self {
        case .bool: return .toggle
        case .string(let v):
            // 字符串形式的 true/false 也识别为开关
            if v.lowercased() == "true" || v.lowercased() == "false" {
                return .toggle
            }
            return .text
        case .int, .double: return .number
        case .null: return .text
        }
    }

    /// 布尔值判断（兼容字符串形式）
    var boolValue: Bool {
        switch self {
        case .bool(let v): return v
        case .string(let v): return v.lowercased() == "true"
        default: return false
        }
    }

    init(raw: RawWidgetValue) {
        switch raw {
        case .string(let v): self = .string(v)
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .bool(let v): self = .bool(v)
        case .null: self = .null
        }
    }
}

/// 控件类型
enum WidgetKind {
    case text
    case number
    case toggle
}

/// 用于解码 widgets_values 中混合类型的元素
enum RawWidgetValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else if container.decodeNil() {
            self = .null
        } else {
            self = .null
        }
    }
}

/// 用于解码 ComfyUI 嵌套数组中混合类型的元素
enum RawLinkValue: Codable {
    case int(Int)
    case string(String)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else if container.decodeNil() {
            self = .null
        } else {
            self = .null
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string(let v): return Int(v)
        case .null: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .null: return nil
        }
    }
}

// MARK: - 节点类型色彩体系

/// 节点类型色彩字典
enum NodeTypeColor {
    /// 根据节点类型返回标题栏颜色
    static func color(for type: String) -> Color {
        let lower = type.lowercased()
        // 加载器类 - 蓝色
        if lower.contains("load") || lower.contains("loader") {
            return Color(red: 0.20, green: 0.45, blue: 0.75)
        }
        // 采样器类 - 红色
        if lower.contains("sampler") || lower.contains("sample") {
            return Color(red: 0.75, green: 0.25, blue: 0.25)
        }
        // 条件/提示词类 - 黄色/橙色
        if lower.contains("condition") || lower.contains("prompt") || lower.contains("encode") {
            return Color(red: 0.80, green: 0.55, blue: 0.10)
        }
        // 潜空间类 - 粉色
        if lower.contains("latent") || lower.contains("vae") {
            return Color(red: 0.70, green: 0.30, blue: 0.60)
        }
        // 图像类 - 绿色
        if lower.contains("image") || lower.contains("save") || lower.contains("preview") {
            return Color(red: 0.25, green: 0.60, blue: 0.35)
        }
        // 模型类 - 紫色
        if lower.contains("model") || lower.contains("dit") || lower.contains("unet") {
            return Color(red: 0.50, green: 0.35, blue: 0.75)
        }
        // 文本/脚本类 - 青色
        if lower.contains("text") || lower.contains("script") || lower.contains("plan") {
            return Color(red: 0.0, green: 0.45, blue: 0.45)
        }
        // 默认 - 深灰
        return Color(red: 0.35, green: 0.35, blue: 0.40)
    }
}

/// 插槽/连线数据类型色彩
enum SlotTypeColor {
    static func color(for type: String?) -> Color {
        guard let type = type else { return .gray }
        switch type.uppercased() {
        case "MODEL": return .orange
        case "CLIP": return .green
        case "VAE": return .purple
        case "LATENT": return .pink
        case "IMAGE": return .blue
        case "CONDITIONING": return .yellow
        case "MASK": return .gray
        case "AUDIO": return .red
        case "VIDEO": return .indigo
        case "PLAN_JSON", "STRING": return .teal
        case "INT", "FLOAT": return .brown
        case "BOOLEAN": return .mint
        default: return .gray
        }
    }
}

// MARK: - 控件参数名注册表

/// 控件参数名映射字典（策略A：内置映射，离线高性能，绝不从inputs插槽名借用）
/// 注意：inputs.name是插槽名（画端口圆点和连线用），widgets_values的参数名必须在此预先定义
enum WidgetNameRegistry {
    /// 根据节点类型返回参数名列表
    static func names(for nodeType: String) -> [String]? {
        let lower = nodeType.lowercased()

        // === MiniMax H3 系列自定义节点（已验证参数顺序）===

        // Ref2VA 参考条件构建器：widgets_values = ["ref2va", 6, "full_ref", ...]
        if lower.contains("ref2vaconditioning") || lower.contains("ref2va_conditioning") {
            return ["模式", "强度", "提示词风格", "参数4", "参数5", "参数6"]
        }

        // Ref2VA 分段采样器：widgets_values = ["ref2va", 10, 20, 5.0, -1, 22, 24, 12.0, ...]
        if lower.contains("segmentedsampler") && lower.contains("ref2va") {
            return [
                "模式", "步数", "引导系数", "采样器", "调度器",
                "种子", "片段数", "上下文长度", "去噪强度",
                "宽度", "高度", "批大小"
            ]
        }

        // 上下文循环接力
        if lower.contains("contextloop") || lower.contains("context_loop") {
            return ["潜空间尾帧", "步数", "引导系数", "去噪强度", "循环次数"]
        }

        // Ref2VA DiT 模型加载器（2个参数）
        if lower.contains("dit") && lower.contains("model") && lower.contains("load") {
            return ["模型文件名", "参数2"]
        }

        // 文本编码器
        if lower.contains("textencode") || lower.contains("text_encode") {
            return ["文本"]
        }

        // VAE 加载器
        if lower.contains("vae") && lower.contains("load") {
            return ["VAE文件名"]
        }

        // 参考图片加载器
        if lower.contains("ref2va") && lower.contains("image") && lower.contains("load") {
            return ["图片"]
        }

        // 参考视频加载器
        if lower.contains("ref2va") && lower.contains("video") && lower.contains("load") {
            return ["视频", "起始帧", "帧数"]
        }

        // 参考音频加载器
        if lower.contains("ref2va") && lower.contains("audio") && lower.contains("load") {
            return ["音频"]
        }

        // 脚本规划台
        if lower.contains("scriptplanner") || lower.contains("script_planner") {
            return ["提示词", "最大片段数", "时长"]
        }

        // === 标准 ComfyUI 节点 ===

        // KSampler 系列
        if lower.contains("ksampler") {
            return ["种子", "步数", "引导系数", "采样器", "调度器", "去噪强度"]
        }

        // Checkpoint 加载器
        if lower.contains("checkpoint") && lower.contains("load") {
            return ["模型文件名"]
        }

        // CLIP 加载器
        if lower.contains("clip") && lower.contains("load") {
            return ["CLIP文件名"]
        }

        // 图片加载器
        if lower.contains("image") && lower.contains("load") {
            return ["图片"]
        }

        // CLIP 文本编码
        if lower.contains("cliptextencode") {
            return ["文本"]
        }

        // 空潜空间
        if lower.contains("emptylatent") {
            return ["宽度", "高度", "批大小"]
        }

        // 保存图片
        if lower.contains("saveimage") {
            return ["文件名前缀"]
        }

        // 视频加载器
        if lower.contains("videoloader") || lower.contains("video_loader") {
            return ["视频", "起始帧", "帧数"]
        }

        // 音频加载器
        if lower.contains("audioloader") || lower.contains("audio_loader") {
            return ["音频"]
        }

        return nil
    }
}

// MARK: - Color Hex 扩展

extension Color {
    /// 从十六进制字符串初始化颜色，支持 "#RRGGBB" 格式
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
