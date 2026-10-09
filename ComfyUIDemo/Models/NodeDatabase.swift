import Foundation

// MARK: - 节点数据库模型（从JSON加载）

/// 参数类型
enum NodeParameterType: String, Codable {
    case string      // 文本
    case integer     // 整数
    case float       // 浮点数
    case boolean     // 布尔开关
    case enumeration // 下拉枚举
}

/// 参数定义
struct NodeParameterDefinition: Codable, Hashable {
    /// 参数名（英文，对应widgets_values索引）
    let name: String
    /// 中文显示名
    let displayName: String
    /// 参数类型
    let type: NodeParameterType
    /// 默认值（字符串形式，根据type解析）
    let defaultValue: String?
    /// 最小值（数值类型）
    let minValue: Double?
    /// 最大值（数值类型）
    let maxValue: Double?
    /// 步长（数值类型）
    let step: Double?
    /// 枚举选项（枚举类型）
    let options: [String]?
    /// 参数描述
    let description: String?
}

/// 插槽定义
struct NodeSlotDefinition: Codable, Hashable {
    /// 插槽名称
    let name: String?
    /// 插槽数据类型
    let type: String?
}

/// 节点分类
enum NodeCategory: String, Codable, CaseIterable {
    case loader      = "模型加载器"
    case sampler     = "采样器"
    case conditioning = "条件构建"
    case codec       = "编解码器"
    case image       = "图像处理"
    case video       = "视频处理"
    case primitive   = "工具与原语"
    case note        = "笔记"
    case minimaxAllInOne = "MiniMax H3 一体化"

    /// 分类图标（SF Symbol）
    var iconName: String {
        switch self {
        case .loader: return "arrow.down.circle"
        case .sampler: return "slider.horizontal.3"
        case .conditioning: return "wand.and.stars"
        case .codec: return "arrow.left.arrow.right"
        case .image: return "photo"
        case .video: return "film"
        case .primitive: return "wrench.and.screwdriver"
        case .note: return "note.text"
        case .minimaxAllInOne: return "sparkles"
        }
    }
}

/// 节点定义
struct NodeDefinition: Codable, Hashable {
    /// 节点类型名（英文，与JSON中的class_type对应）
    let type: String
    /// 中文显示名
    let displayName: String
    /// 主题色（hex）
    let colorHex: String
    /// 输入插槽列表
    let inputs: [NodeSlotDefinition]
    /// 输出插槽列表
    let outputs: [NodeSlotDefinition]
    /// 参数定义列表（与widgets_values顺序对应）
    let parameters: [NodeParameterDefinition]
    /// 节点描述
    let description: String?
    /// 所属分类（运行时赋值，不在JSON中）
    var category: NodeCategory = .primitive

    // 自定义解码：category在JSON中不存在，使用默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        displayName = try container.decode(String.self, forKey: .displayName)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        inputs = try container.decode([NodeSlotDefinition].self, forKey: .inputs)
        outputs = try container.decode([NodeSlotDefinition].self, forKey: .outputs)
        parameters = try container.decode([NodeParameterDefinition].self, forKey: .parameters)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        category = .primitive // JSON中不包含category，由数据库加载时赋值
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(parameters, forKey: .parameters)
        try container.encodeIfPresent(description, forKey: .description)
    }

    private enum CodingKeys: String, CodingKey {
        case type, displayName, colorHex, inputs, outputs, parameters, description
    }
}

// MARK: - JSON数据库文件结构

/// 单个分类数据库JSON结构
struct NodeCategoryDatabase: Codable {
    /// 分类名（中文）
    let category: String
    /// 分类图标
    let categoryIcon: String
    /// 该分类下的节点列表
    let nodes: [NodeDefinition]
}

// MARK: - 节点数据库（从Bundle JSON加载）

enum NodeDatabase {
    /// 所有节点（按类型名索引）
    static private(set) var allNodes: [String: NodeDefinition] = [:]
    /// 分类到节点列表的映射
    static private(set) var nodesByCategory: [NodeCategory: [NodeDefinition]] = [:]
    /// 是否已加载
    static private(set) var isLoaded = false

    /// 数据库JSON文件名列表（按功能板块划分）
    private static let databaseFiles: [(file: String, category: NodeCategory)] = [
        ("loaders", .loader),
        ("sampling", .sampler),
        ("conditioning", .conditioning),
        ("codec", .codec),
        ("image", .image),
        ("video", .video),
        ("primitives", .primitive),
        ("note", .note),
        ("minimax_allinone", .minimaxAllInOne),
    ]

    /// 加载所有节点数据库（从Bundle读取JSON）
    static func loadIfNeeded() {
        guard !isLoaded else { return }

        var all: [String: NodeDefinition] = [:]
        var byCategory: [NodeCategory: [NodeDefinition]] = [:]
        var loadedCount = 0

        for (fileName, category) in databaseFiles {
            // XcodeGen将resources目录下的文件直接打包到bundle根目录，不保留子目录结构
            guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
                print("[节点库] 未找到文件: \(fileName).json")
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let categoryDB = try decoder.decode(NodeCategoryDatabase.self, from: data)
                var nodes = categoryDB.nodes
                for i in 0..<nodes.count {
                    nodes[i].category = category
                }
                byCategory[category] = nodes
                for node in nodes {
                    all[node.type] = node
                }
                loadedCount += 1
                print("[节点库] 已加载 \(fileName): \(nodes.count)个节点")
            } catch {
                print("[节点库] 解码失败 \(fileName).json: \(error)")
            }
        }

        allNodes = all
        nodesByCategory = byCategory
        isLoaded = true
        print("[节点库] 加载完成: 共\(loadedCount)个分类, \(all.count)个节点")
    }

    /// 根据节点类型名查找定义
    static func definition(for nodeType: String) -> NodeDefinition? {
        loadIfNeeded()
        return allNodes[nodeType]
    }

    /// 获取指定分类的所有节点
    static func nodes(in category: NodeCategory) -> [NodeDefinition] {
        loadIfNeeded()
        return nodesByCategory[category] ?? []
    }

    /// 所有分类（按固定顺序）
    static var allCategories: [NodeCategory] {
        NodeCategory.allCases
    }
}

// MARK: - 节点创建辅助

extension NodeDefinition {
    /// 根据节点定义创建NodeModel
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
