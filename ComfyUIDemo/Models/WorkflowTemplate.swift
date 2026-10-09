import Foundation

// MARK: - 工作流模板模型

/// 工作流模板元数据
struct WorkflowTemplate: Identifiable, Hashable {
    /// 唯一标识
    let id: String
    /// 中文显示名称
    let name: String
    /// 英文名称
    let nameEn: String
    /// 分类标签
    let category: String
    /// 模板JSON文件名（不含扩展名）
    let fileName: String
    /// 模板描述
    let description: String
    /// SF Symbol 图标名
    let icon: String

    /// 从Bundle加载模板JSON并解析为WorkflowModel
    func loadWorkflow() -> WorkflowModel? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return JsonParser.parseWorkflow(json: jsonString)
    }
}

// MARK: - 模板数据库

/// 内置工作流模板数据库（从 Comfy-Org/workflow_templates 官方仓库下载）
enum WorkflowTemplateDatabase {

    // MARK: - MiniMax H3 系列

    /// MiniMax H3 文生视频模板
    static let minimaxH3T2V = WorkflowTemplate(
        id: "minimax-h3-t2v",
        name: "H3 文生视频",
        nameEn: "MiniMax H3 Text to Video",
        category: "MiniMax H3",
        fileName: "video_minimax_h3_t2v",
        description: "根据文本提示词生成视频，自带原生立体声音频",
        icon: "text.bubble"
    )

    /// MiniMax H3 图生视频模板
    static let minimaxH3I2V = WorkflowTemplate(
        id: "minimax-h3-i2v",
        name: "H3 图生视频",
        nameEn: "MiniMax H3 Image to Video",
        category: "MiniMax H3",
        fileName: "video_minimax_h3_i2v",
        description: "以起始图片为首帧生成视频，保留画面风格与主体",
        icon: "photo"
    )

    /// MiniMax H3 参考生视频模板
    static let minimaxH3R2V = WorkflowTemplate(
        id: "minimax-h3-r2v",
        name: "H3 参考生视频",
        nameEn: "MiniMax H3 Reference to Video",
        category: "MiniMax H3",
        fileName: "video_minimax_h3_r2v",
        description: "支持最多9张参考图+3段参考视频+3段音频，融合角色/动作/镜头/声音",
        icon: "square.stack.3d.up"
    )

    // MARK: - 全部分类与列表

    /// 所有可用模板（按分类分组展示）
    static let allTemplates: [WorkflowTemplate] = [
        minimaxH3T2V,
        minimaxH3I2V,
        minimaxH3R2V
    ]

    /// 所有分类名称（去重，保持顺序）
    static var allCategories: [String] {
        var seen = Set<String>()
        return allTemplates.compactMap { template in
            if seen.contains(template.category) {
                return nil
            }
            seen.insert(template.category)
            return template.category
        }
    }

    /// 按分类筛选模板
    static func templates(in category: String) -> [WorkflowTemplate] {
        allTemplates.filter { $0.category == category }
    }
}
