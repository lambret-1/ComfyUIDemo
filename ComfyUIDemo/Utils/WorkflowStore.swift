import Foundation

/// 工作流本地存储工具：负责保存/加载上次工作流、保存编辑后的工作流
enum WorkflowStore {
    /// UserDefaults 键名
    private static let lastWorkflowKey = "com.comfyui.lastWorkflowJson"
    private static let lastWorkflowNameKey = "com.comfyui.lastWorkflowName"

    /// 保存上次成功加载的工作流 JSON
    static func saveLastWorkflow(json: String, name: String = "未命名工作流") {
        UserDefaults.standard.set(json, forKey: lastWorkflowKey)
        UserDefaults.standard.set(name, forKey: lastWorkflowNameKey)
        UserDefaults.standard.synchronize()
    }

    /// 加载上次保存的工作流 JSON
    static func loadLastWorkflow() -> (json: String, name: String)? {
        guard let json = UserDefaults.standard.string(forKey: lastWorkflowKey),
              !json.isEmpty else { return nil }
        let name = UserDefaults.standard.string(forKey: lastWorkflowNameKey) ?? "上次工作流"
        return (json, name)
    }

    /// 是否存在上次工作流
    static var hasLastWorkflow: Bool {
        loadLastWorkflow() != nil
    }

    /// 清除上次工作流记录
    static func clearLastWorkflow() {
        UserDefaults.standard.removeObject(forKey: lastWorkflowKey)
        UserDefaults.standard.removeObject(forKey: lastWorkflowNameKey)
        UserDefaults.standard.synchronize()
    }

    /// 将 WorkflowModel 序列化为 JSON 字符串
    static func serializeWorkflow(_ workflow: WorkflowModel) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(workflow) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 保存当前编辑后的工作流到文档目录
    @discardableResult
    static func saveWorkflowToDocuments(_ workflow: WorkflowModel, name: String? = nil) -> Bool {
        guard let json = serializeWorkflow(workflow) else { return false }
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = name ?? "workflow-\(formatter.string(from: Date())).json"
        let fileUrl = docDir.appendingPathComponent(fileName)
        do {
            try json.write(to: fileUrl, atomically: true, encoding: .utf8)
            // 同时更新为上次工作流
            saveLastWorkflow(json: json, name: name ?? "已保存工作流")
            return true
        } catch {
            return false
        }
    }
}
