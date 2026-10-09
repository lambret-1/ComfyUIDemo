import Foundation

// MARK: - 节点数据库模型

/// 参数类型枚举
enum NodeParameterType: String, Codable {
    case string      // 文本
    case integer     // 整数
    case float       // 浮点数
    case boolean     // 布尔开关
    case enumeration // 下拉枚举
}

/// 节点参数定义
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

    init(name: String, displayName: String, type: NodeParameterType,
         defaultValue: String? = nil, minValue: Double? = nil,
         maxValue: Double? = nil, step: Double? = nil,
         options: [String]? = nil, description: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.type = type
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.options = options
        self.description = description
    }
}

/// 节点插槽定义
struct NodeSlotDefinition: Codable, Hashable {
    /// 插槽名（英文）
    let name: String
    /// 中文显示名
    let displayName: String
    /// 数据类型（如 MODEL/CLIP/VAE/CONDITIONING/LATENT/IMAGE/VIDEO/AUDIO 等）
    let type: String
    /// 是否可选
    let optional: Bool

    init(name: String, displayName: String, type: String, optional: Bool = false) {
        self.name = name
        self.displayName = displayName
        self.type = type
        self.optional = optional
    }
}

/// 节点分类
enum NodeCategory: String, Codable {
    case loader      = "加载器"
    case sampler     = "采样器"
    case conditioning = "条件构建"
    case encoder     = "编码器"
    case processing  = "处理"
    case utility     = "工具"
}

/// 完整节点定义
struct NodeDefinition: Codable, Hashable {
    /// 节点类型名（英文，与JSON中的class_type对应）
    let type: String
    /// 中文显示名
    let displayName: String
    /// 节点分类
    let category: NodeCategory
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

    init(type: String, displayName: String, category: NodeCategory,
         colorHex: String, inputs: [NodeSlotDefinition],
         outputs: [NodeSlotDefinition], parameters: [NodeParameterDefinition],
         description: String? = nil) {
        self.type = type
        self.displayName = displayName
        self.category = category
        self.colorHex = colorHex
        self.inputs = inputs
        self.outputs = outputs
        self.parameters = parameters
        self.description = description
    }
}

// MARK: - MiniMax H3 官方节点数据库

/// MiniMax H3 系列节点数据库
enum MiniMaxH3NodeDatabase {
    /// 所有MiniMaxH3官方节点定义（按类型名索引）
    static let allNodes: [String: NodeDefinition] = [
        // MARK: 加载器类

        /// Ref2VA DiT 模型加载器
        "MiniMaxH3Ref2VAModelLoader": NodeDefinition(
            type: "MiniMaxH3Ref2VAModelLoader",
            displayName: "Ref2VA DiT 模型加载",
            category: .loader,
            colorHex: "#2563EB",
            inputs: [],
            outputs: [
                NodeSlotDefinition(name: "MODEL", displayName: "模型", type: "MODEL")
            ],
            parameters: [
                NodeParameterDefinition(name: "model_name", displayName: "模型文件名", type: .string,
                                        defaultValue: "minimax_h3_ref2va_pruned_int8_converted.safetensors",
                                        description: "Ref2VA DiT 模型文件路径"),
                NodeParameterDefinition(name: "device", displayName: "运行设备", type: .enumeration,
                                        defaultValue: "default", options: ["default", "cpu", "cuda"])
            ],
            description: "加载 MiniMax H3 Ref2VA DiT 模型"
        ),

        /// VAE 加载器
        "MiniMaxH3VAELoader": NodeDefinition(
            type: "MiniMaxH3VAELoader",
            displayName: "VAE 加载器",
            category: .loader,
            colorHex: "#2563EB",
            inputs: [],
            outputs: [
                NodeSlotDefinition(name: "VIDEO_VAE", displayName: "视频VAE", type: "VAE"),
                NodeSlotDefinition(name: "AUDIO_VAE", displayName: "音频VAE", type: "VAE")
            ],
            parameters: [
                NodeParameterDefinition(name: "video_vae_name", displayName: "视频VAE文件名", type: .string,
                                        defaultValue: "minimax_h3_video_vae.safetensors"),
                NodeParameterDefinition(name: "audio_vae_name", displayName: "音频VAE文件名", type: .string,
                                        defaultValue: "minimax_h3_audio_vae.safetensors")
            ],
            description: "加载 MiniMax H3 视频和音频 VAE"
        ),

        /// 参考图片加载器
        "MiniMaxH3Ref2VAImageLoader": NodeDefinition(
            type: "MiniMaxH3Ref2VAImageLoader",
            displayName: "参考图片加载器",
            category: .loader,
            colorHex: "#2563EB",
            inputs: [],
            outputs: [
                NodeSlotDefinition(name: "images", displayName: "图像组", type: "IMAGE")
            ],
            parameters: [
                NodeParameterDefinition(name: "image", displayName: "图片", type: .string,
                                        description: "参考图片文件")
            ],
            description: "加载 Ref2VA 参考图片"
        ),

        /// 参考视频加载器
        "MiniMaxH3Ref2VAVideoLoader": NodeDefinition(
            type: "MiniMaxH3Ref2VAVideoLoader",
            displayName: "参考视频加载器",
            category: .loader,
            colorHex: "#2563EB",
            inputs: [],
            outputs: [
                NodeSlotDefinition(name: "videos", displayName: "视频组", type: "VIDEO"),
                NodeSlotDefinition(name: "audios", displayName: "音频组", type: "AUDIO")
            ],
            parameters: [
                NodeParameterDefinition(name: "video", displayName: "视频", type: .string),
                NodeParameterDefinition(name: "start_frame", displayName: "起始帧", type: .integer,
                                        defaultValue: "0", minValue: 0, step: 1),
                NodeParameterDefinition(name: "frame_count", displayName: "帧数", type: .integer,
                                        defaultValue: "16", minValue: 1, step: 1)
            ],
            description: "加载 Ref2VA 参考视频（含音轨）"
        ),

        /// 参考音频加载器
        "MiniMaxH3Ref2VAAudioLoader": NodeDefinition(
            type: "MiniMaxH3Ref2VAAudioLoader",
            displayName: "参考音频加载器",
            category: .loader,
            colorHex: "#2563EB",
            inputs: [],
            outputs: [
                NodeSlotDefinition(name: "audios", displayName: "音频组", type: "AUDIO")
            ],
            parameters: [
                NodeParameterDefinition(name: "audio", displayName: "音频", type: .string)
            ],
            description: "加载 Ref2VA 参考音频"
        ),

        // MARK: 编码器类

        /// 文本编码器（Qwen3-VL）
        "MiniMaxH3TextEncoder": NodeDefinition(
            type: "MiniMaxH3TextEncoder",
            displayName: "文本编码器（Qwen3-VL）",
            category: .encoder,
            colorHex: "#CA8A04",
            inputs: [
                NodeSlotDefinition(name: "plan_json", displayName: "规划JSON", type: "PLAN_JSON", optional: true),
                NodeSlotDefinition(name: "total_segments", displayName: "总片段数", type: "INT", optional: true)
            ],
            outputs: [
                NodeSlotDefinition(name: "CLIP", displayName: "文本编码", type: "CLIP")
            ],
            parameters: [
                NodeParameterDefinition(name: "text_model", displayName: "文本", type: .enumeration,
                                        defaultValue: "Qwen3-VL-32B", options: ["Qwen3-VL-32B", "Qwen3-VL-7B"]),
                NodeParameterDefinition(name: "max_tokens", displayName: "最大Token数", type: .integer,
                                        defaultValue: "50", minValue: 1, maxValue: 4096, step: 1)
            ],
            description: "使用 Qwen3-VL 模型编码文本提示词"
        ),

        // MARK: 条件构建类

        /// Ref2VA 参考条件构建器
        "MiniMaxH3Ref2VAConditioning": NodeDefinition(
            type: "MiniMaxH3Ref2VAConditioning",
            displayName: "Ref2VA 参考条件构建器",
            category: .conditioning,
            colorHex: "#CA8A04",
            inputs: [
                NodeSlotDefinition(name: "ref_images", displayName: "参考图片", type: "IMAGE"),
                NodeSlotDefinition(name: "ref_videos", displayName: "参考视频", type: "VIDEO"),
                NodeSlotDefinition(name: "ref_video_audios", displayName: "参考视频原声", type: "AUDIO"),
                NodeSlotDefinition(name: "ref_audios", displayName: "参考音频", type: "AUDIO"),
                NodeSlotDefinition(name: "plan_json", displayName: "规划JSON", type: "PLAN_JSON"),
                NodeSlotDefinition(name: "clip", displayName: "文本编码", type: "CLIP")
            ],
            outputs: [
                NodeSlotDefinition(name: "conditioning", displayName: "条件", type: "CONDITIONING")
            ],
            parameters: [
                NodeParameterDefinition(name: "mode", displayName: "模式", type: .enumeration,
                                        defaultValue: "ref2va", options: ["ref2va", "full_ref", "text_only"]),
                NodeParameterDefinition(name: "strength", displayName: "强度", type: .float,
                                        defaultValue: "6", minValue: 0, maxValue: 100, step: 0.5),
                NodeParameterDefinition(name: "prompt_style", displayName: "提示词风格", type: .enumeration,
                                        defaultValue: "full_ref", options: ["full_ref", "minimal", "detailed"]),
                NodeParameterDefinition(name: "param4", displayName: "参数4", type: .string),
                NodeParameterDefinition(name: "param5", displayName: "参数5", type: .string),
                NodeParameterDefinition(name: "param6", displayName: "参数6", type: .string)
            ],
            description: "构建 Ref2VA 参考条件，融合图片/视频/音频/文本多模态输入"
        ),

        // MARK: 采样器类

        /// Ref2VA 分段采样器（含 Context Loop）
        "MiniMaxH3SegmentedSamplerRef2VA": NodeDefinition(
            type: "MiniMaxH3SegmentedSamplerRef2VA",
            displayName: "Ref2VA 分段采样器（含 Context Loop）",
            category: .sampler,
            colorHex: "#B91C1C",
            inputs: [
                NodeSlotDefinition(name: "model", displayName: "模型", type: "MODEL"),
                NodeSlotDefinition(name: "conditioning", displayName: "条件", type: "CONDITIONING"),
                NodeSlotDefinition(name: "video_vae", displayName: "视频VAE", type: "VAE"),
                NodeSlotDefinition(name: "audio_vae", displayName: "音频VAE", type: "VAE"),
                NodeSlotDefinition(name: "prev_latent_tail", displayName: "上一段尾帧", type: "LATENT", optional: true),
                NodeSlotDefinition(name: "plan_json", displayName: "规划JSON", type: "PLAN_JSON", optional: true)
            ],
            outputs: [
                NodeSlotDefinition(name: "video_latent", displayName: "视频潜空间", type: "LATENT"),
                NodeSlotDefinition(name: "latent_tail", displayName: "潜空间尾帧", type: "LATENT"),
                NodeSlotDefinition(name: "segment_index", displayName: "片段索引", type: "INT"),
                NodeSlotDefinition(name: "audio_latent", displayName: "音频潜空间", type: "LATENT")
            ],
            parameters: [
                NodeParameterDefinition(name: "mode", displayName: "模式", type: .enumeration,
                                        defaultValue: "ref2va", options: ["ref2va", "standard"]),
                NodeParameterDefinition(name: "steps", displayName: "步数", type: .integer,
                                        defaultValue: "10", minValue: 1, maxValue: 100, step: 1),
                NodeParameterDefinition(name: "cfg", displayName: "引导系数", type: .float,
                                        defaultValue: "20", minValue: 1, maxValue: 30, step: 0.5),
                NodeParameterDefinition(name: "sampler_name", displayName: "采样器", type: .enumeration,
                                        defaultValue: "5", options: ["euler", "dpmpp_2m", "dpmpp_sde", "heun", "ddim"]),
                NodeParameterDefinition(name: "scheduler", displayName: "调度器", type: .enumeration,
                                        defaultValue: "-1", options: ["normal", "karras", "exponential", "sgm_uniform"]),
                NodeParameterDefinition(name: "seed", displayName: "种子", type: .integer,
                                        defaultValue: "-1", minValue: -1, maxValue: 4294967294, step: 1),
                NodeParameterDefinition(name: "segment_count", displayName: "片段数", type: .integer,
                                        defaultValue: "22", minValue: 1, maxValue: 100, step: 1),
                NodeParameterDefinition(name: "context_length", displayName: "上下文长度", type: .integer,
                                        defaultValue: "24", minValue: 1, maxValue: 100, step: 1),
                NodeParameterDefinition(name: "denoise", displayName: "去噪强度", type: .float,
                                        defaultValue: "12", minValue: 0, maxValue: 1, step: 0.01),
                NodeParameterDefinition(name: "width", displayName: "宽度", type: .integer,
                                        defaultValue: "1344", minValue: 256, maxValue: 4096, step: 16),
                NodeParameterDefinition(name: "height", displayName: "高度", type: .integer,
                                        defaultValue: "768", minValue: 256, maxValue: 4096, step: 16),
                NodeParameterDefinition(name: "batch_size", displayName: "批大小", type: .integer,
                                        defaultValue: "1", minValue: 1, maxValue: 16, step: 1)
            ],
            description: "Ref2VA 分段采样器，支持 Context Loop 循环接力生成长视频"
        ),

        /// 上下文循环接力
        "MiniMaxH3ContextLoop": NodeDefinition(
            type: "MiniMaxH3ContextLoop",
            displayName: "上下文循环接力",
            category: .sampler,
            colorHex: "#0F766E",
            inputs: [
                NodeSlotDefinition(name: "latent_tail", displayName: "潜空间尾帧", type: "LATENT")
            ],
            outputs: [
                NodeSlotDefinition(name: "context_latent", displayName: "上下文潜空间", type: "LATENT")
            ],
            parameters: [
                NodeParameterDefinition(name: "latent_tail_frames", displayName: "潜空间尾帧", type: .integer,
                                        defaultValue: "22", minValue: 1, maxValue: 100, step: 1),
                NodeParameterDefinition(name: "steps", displayName: "步数", type: .integer,
                                        defaultValue: "24", minValue: 1, maxValue: 100, step: 1),
                NodeParameterDefinition(name: "cfg", displayName: "引导系数", type: .float,
                                        defaultValue: "20", minValue: 1, maxValue: 30, step: 0.5),
                NodeParameterDefinition(name: "denoise", displayName: "去噪强度", type: .float,
                                        defaultValue: "0.8", minValue: 0, maxValue: 1, step: 0.01),
                NodeParameterDefinition(name: "loop_count", displayName: "循环次数", type: .integer,
                                        defaultValue: "1", minValue: 1, maxValue: 100, step: 1)
            ],
            description: "上下文循环接力，将上一段尾帧作为下一段的上下文输入，实现长视频生成"
        ),

        // MARK: 处理类

        /// 剧本分段规划台
        "MiniMaxH3ScriptPlanner": NodeDefinition(
            type: "MiniMaxH3ScriptPlanner",
            displayName: "剧本分段规划台",
            category: .processing,
            colorHex: "#0F766E",
            inputs: [],
            outputs: [
                NodeSlotDefinition(name: "plan_json", displayName: "规划JSON", type: "PLAN_JSON"),
                NodeSlotDefinition(name: "total_segments", displayName: "总片段数", type: "INT")
            ],
            parameters: [
                NodeParameterDefinition(name: "prompt", displayName: "提示词", type: .string,
                                        description: "视频生成提示词"),
                NodeParameterDefinition(name: "max_segments", displayName: "最大片段数", type: .integer,
                                        defaultValue: "10", minValue: 1, maxValue: 100, step: 1),
                NodeParameterDefinition(name: "duration", displayName: "时长", type: .float,
                                        defaultValue: "30", minValue: 1, maxValue: 600, step: 1)
            ],
            description: "将长提示词自动分段规划，生成多段视频的拍摄计划"
        )
    ]

    /// 根据节点类型名获取节点定义
    static func definition(for nodeType: String) -> NodeDefinition? {
        // 精确匹配
        if let def = allNodes[nodeType] { return def }
        // 不区分大小写匹配
        let lower = nodeType.lowercased()
        return allNodes.values.first { $0.type.lowercased() == lower }
    }

    /// 获取所有节点定义列表
    static var allDefinitions: [NodeDefinition] {
        Array(allNodes.values)
    }

    /// 按分类获取节点
    static func nodes(in category: NodeCategory) -> [NodeDefinition] {
        allNodes.values.filter { $0.category == category }
    }
}
