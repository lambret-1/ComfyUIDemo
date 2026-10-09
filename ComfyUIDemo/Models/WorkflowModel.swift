import Foundation

/// 工作流根模型，对应 ComfyUI 导出的 workflow.json 顶层结构
struct WorkflowModel: Codable {
    /// 节点列表
    var nodes: [NodeModel]
    /// 连线列表（ComfyUI 原生为嵌套数组，已在解析器中转换为结构化模型）
    var links: [LinkModel]

    /// 以节点编号为键的快速查找表
    var nodeMap: [Int: NodeModel] {
        nodes.reduce(into: [:]) { map, node in
            map[node.id] = node
        }
    }

    /// 自定义解码：兼容 ComfyUI 原生 links 为嵌套数组的格式
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decode([NodeModel].self, forKey: .nodes)

        // ComfyUI 原生 links 是 [[link_id, source_id, source_slot, target_id, target_slot, type]]
        // 同时兼容已转换为对象数组的格式
        if let nestedLinks = try? container.decode([[RawLinkValue]].self, forKey: .links) {
            links = nestedLinks.compactMap { LinkModel(rawArray: $0) }
        } else if let objectLinks = try? container.decode([LinkModel].self, forKey: .links) {
            links = objectLinks
        } else {
            links = []
        }
    }
}

/// 节点模型，对应 ComfyUI nodes 数组中的单个节点
struct NodeModel: Codable, Identifiable, Hashable {
    /// 节点编号（ComfyUI 中为整数）
    let id: Int
    /// 节点类型名称，如 "CheckpointLoaderSimple"
    let type: String
    /// 节点在画布中的位置 [x, y]
    let pos: [Double]
    /// 节点尺寸 [width, height]
    let size: [Double]
    /// 输入插槽列表
    let inputs: [SlotModel]?
    /// 输出插槽列表
    let outputs: [SlotModel]?
    /// 节点标题（可选，ComfyUI 中可能为 widgets_values 或 title）
    let title: String?

    /// 计算属性：节点左上角坐标
    var position: CGPoint {
        guard pos.count >= 2 else { return .zero }
        return CGPoint(x: pos[0], y: pos[1])
    }

    /// 计算属性：节点尺寸
    var nodeSize: CGSize {
        guard size.count >= 2 else { return CGSize(width: 200, height: 80) }
        return CGSize(width: max(size[0], 80), height: max(size[1], 40))
    }

    /// 节点显示标题：优先 title，其次 type
    var displayTitle: String {
        title?.isEmpty == false ? title! : type
    }

    enum CodingKeys: String, CodingKey {
        case id, type, pos, size, inputs, outputs, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 兼容 id 为字符串或整数的情况
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
        } else if let strId = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(strId) {
            id = parsed
        } else {
            id = 0
        }
        type = try container.decode(String.self, forKey: .type)
        pos = try container.decode([Double].self, forKey: .pos)
        size = try container.decode([Double].self, forKey: .size)
        inputs = try container.decodeIfPresent([SlotModel].self, forKey: .inputs)
        outputs = try container.decodeIfPresent([SlotModel].self, forKey: .outputs)
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: NodeModel, rhs: NodeModel) -> Bool {
        lhs.id == rhs.id
    }
}

/// 插槽模型，对应节点的 inputs / outputs 数组元素
struct SlotModel: Codable, Hashable {
    /// 插槽名称
    let name: String?
    /// 插槽数据类型，如 "MODEL"、"CLIP"、"LATENT"
    let type: String?
    /// 插槽索引（ComfyUI 中部分节点提供）
    let slotIndex: Int?

    enum CodingKeys: String, CodingKey {
        case name, type
        case slotIndex = "slot_index"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        slotIndex = try container.decodeIfPresent(Int.self, forKey: .slotIndex)
    }
}

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
    /// 格式: [link_id(Int), source_id(Int), source_slot(Int), target_id(Int), target_slot(Int), type(String)]
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
