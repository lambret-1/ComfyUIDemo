import Foundation

/// 插槽名称本地化管理器：数据层存英文，UI层显示中文
/// 严格遵循"数据存英文，UI显中文"原则，导出JSON时使用原始英文值
enum SlotLocalization {

    // MARK: - 基础插槽字典（ComfyUI 核心节点）

    private static let baseDict: [String: String] = [
        "model": "模型",
        "clip": "文本编码",
        "vae": "VAE",
        "conditioning": "条件",
        "latent": "潜空间",
        "samples": "样本",
        "image": "图像",
        "images": "图像组",
        "video": "视频",
        "videos": "视频组",
        "audio": "音频",
        "audios": "音频组",
        "seed": "种子",
        "steps": "步数",
        "cfg": "引导系数",
        "sampler_name": "采样器",
        "scheduler": "调度器",
        "denoise": "去噪强度",
        "width": "宽度",
        "height": "高度",
        "batch_size": "批量",
        "prompt": "提示词",
        "negative": "负向提示词",
        "text": "文本",
        "string": "字符串",
        "int": "整数",
        "float": "浮点数",
        "boolean": "布尔",
        "mask": "遮罩",
        "pixels": "像素",
        "control_net": "控制网",
        "style": "风格",
        "lora_name": "LoRA名称",
        "strength_model": "模型强度",
        "strength_clip": "CLIP强度",
        "ckpt_name": "模型文件名",
        "vae_name": "VAE文件名",
        "clip_name": "CLIP文件名",
        "filename_prefix": "文件名前缀",
        "save_image": "保存图像",
        "preview": "预览"
    ]

    // MARK: - 扩展插槽字典（MiniMax H3 等自定义节点）

    private static let customDict: [String: String] = [
        "video_latent": "视频潜空间",
        "audio_latent": "音频潜空间",
        "latent_tail": "潜空间尾帧",
        "prev_latent_tail": "上一段尾帧",
        "context_latent": "上下文潜空间",
        "segment_index": "片段索引",
        "plan_json": "规划JSON",
        "total_segments": "总片段数",
        "ref_images": "参考图片",
        "ref_videos": "参考视频",
        "ref_video_audios": "参考视频原声",
        "ref_audios": "参考音频",
        "ref2va": "Ref2VA模式",
        "video_vae": "视频VAE",
        "audio_vae": "音频VAE",
        "dit_model": "DiT模型",
        "context_loop": "上下文循环",
        "script_plan": "脚本规划",
        "text_encoder": "文本编码器",
        "qwen3_vl": "Qwen3-VL",
        "minimax_h3": "MiniMax H3",
        "segmented_sampler": "分段采样器",
        "conditioning_builder": "条件构建器",
        "script_planner": "脚本规划器",
        "image_loader": "图片加载器",
        "video_loader": "视频加载器",
        "audio_loader": "音频加载器",
        "model_loader": "模型加载器",
        "context_loop_receiver": "上下文循环接力"
    ]

    // MARK: - 公共接口

    /// 获取插槽名称的中文本地化
    /// - Parameter englishName: 原始英文名称
    /// - Returns: 中文名称，未命中则返回英文原值
    static func localized(for englishName: String) -> String {
        let key = englishName.lowercased()

        // 1. 优先查自定义字典
        if let custom = customDict[key] {
            return custom
        }

        // 2. 其次查基础字典
        if let base = baseDict[key] {
            return base
        }

        // 3. 动态后缀/前缀匹配（兜底自动翻译）
        if key.hasSuffix("_vae") {
            let prefix = key.replacingOccurrences(of: "_vae", with: "")
            return "\(localized(for: prefix)) VAE"
        }
        if key.hasSuffix("_latent") {
            let prefix = key.replacingOccurrences(of: "_latent", with: "")
            return "\(localized(for: prefix))潜空间"
        }
        if key.hasSuffix("_name") {
            let prefix = key.replacingOccurrences(of: "_name", with: "")
            return "\(localized(for: prefix))名称"
        }
        if key.hasSuffix("_loader") {
            let prefix = key.replacingOccurrences(of: "_loader", with: "")
            return "\(localized(for: prefix))加载器"
        }
        if key.hasSuffix("_encoder") {
            let prefix = key.replacingOccurrences(of: "_encoder", with: "")
            return "\(localized(for: prefix))编码器"
        }
        if key.hasPrefix("ref_") {
            let suffix = key.replacingOccurrences(of: "ref_", with: "")
            return "参考\(localized(for: suffix))"
        }
        if key.hasPrefix("prev_") {
            let suffix = key.replacingOccurrences(of: "prev_", with: "")
            return "上一\(localized(for: suffix))"
        }

        // 4. 无匹配项，返回英文原值（绝不返回空字符串）
        return englishName
    }

    /// 获取双语对照名称：中文名 (english_name)
    /// - Parameter englishName: 原始英文名称
    /// - Returns: 双语对照字符串，用于详情弹窗
    static func bilingual(for englishName: String) -> String {
        let localized = self.localized(for: englishName)
        if localized == englishName {
            return englishName
        }
        return "\(localized) (\(englishName))"
    }
}
