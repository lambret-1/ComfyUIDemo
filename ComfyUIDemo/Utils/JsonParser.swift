import Foundation

/// JSON 解析工具，负责将 ComfyUI 工作流 JSON 字符串解析为模型
enum JsonParser {

    /// 解析工作流 JSON 字符串
    /// - Parameter json: JSON 文本
    /// - Returns: 解析成功返回 WorkflowModel，失败返回 nil
    static func parseWorkflow(json: String) -> WorkflowModel? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        // 忽略 ComfyUI 导出 JSON 中的额外未知字段，避免解析崩溃
        decoder.userInfo[CodingUserInfoKey(rawValue: "ignoreUnknown")!] = true
        do {
            return try decoder.decode(WorkflowModel.self, from: data)
        } catch {
            return nil
        }
    }

    /// 校验 JSON 格式是否合法
    static func isValidJson(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
