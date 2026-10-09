import Foundation

/// 插槽名称本地化管理器：数据层存英文，UI层显示中文
/// 词典严格基于 MiniMax H3 三份模板（T2V/I2V/R2V）实际使用的插槽名称构建
/// 严格遵循"数据存英文，UI显中文"原则，导出JSON时使用原始英文值
enum SlotLocalization {

    // MARK: - H3 模板插槽翻译词典（基于 T2V/I2V/R2V 三份 JSON 实际插槽名）

    private static let h3Dict: [String: String] = [
        // === 输出插槽类型名（大写）===
        "audio": "音频",
        "bool": "布尔",
        "boolean": "布尔",
        "clip": "文本编码",
        "float": "浮点数",
        "guider": "引导器",
        "image": "图像",
        "int": "整数",
        "latent": "潜空间",
        "mask": "遮罩",
        "model": "模型",
        "noise": "噪声",
        "sampler": "采样器",
        "sigmas": "噪声调度",
        "string": "文本",
        "vae": "VAE",
        "video": "视频",

        // === 输入插槽名（小写）===
        "audio_vae": "音频VAE",
        "batch_size": "批量大小",
        "conditioning": "条件",
        "denoised_output": "去噪输出",
        "first_frame": "首帧",
        "height": "高度",
        "images": "图像组",
        "last_frame": "尾帧",
        "latent_image": "潜空间图像",
        "length": "长度",
        "on_false": "关时输出",
        "on_true": "开时输出",
        "output": "输出",
        "positive": "正向条件",
        "prompt": "提示词",
        "samples": "样本",
        "steps": "步数",
        "strength_model_1": "模型强度1",
        "switch": "开关",
        "vae_name_1": "VAE文件名1",
        "value": "值",
        "value_1": "值1",
        "value_2": "值2",
        "values.a": "数值A",
        "values.b": "数值B",
        "width": "宽度",

        // === 参考生视频（R2V）多参考插槽名 ===
        "ref_audios.ref_audio_0": "参考音频0",
        "ref_images.ref_image_0": "参考图片0",
        "ref_images.ref_image_1": "参考图片1",
        "ref_images.ref_image_2": "参考图片2",
        "ref_video_audios.ref_video_audio_0": "参考视频原声0",
        "ref_videos.ref_video_0": "参考视频0",
    ]

    // MARK: - 公共接口

    /// 获取插槽名称的中文本地化
    /// - Parameter englishName: 原始英文名称
    /// - Returns: 中文名称，未命中则返回英文原值
    static func localized(for englishName: String) -> String {
        let key = englishName.lowercased()

        // 1. 优先查 H3 模板词典
        if let translated = h3Dict[key] {
            return translated
        }

        // 2. 动态后缀/前缀匹配（兜底自动翻译）
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

        // 3. 无匹配项，返回英文原值（绝不返回空字符串）
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
