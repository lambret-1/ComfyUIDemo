import SwiftUI
import UniformTypeIdentifiers

/// JSON 导入页面：支持粘贴文本、从文件选择、本地保存、语法校验
/// 独立全屏页面，自带导航栏与返回按钮
struct JsonImportView: View {
    /// 输入的 JSON 文本
    @State private var inputText: String = ""
    /// 是否显示文件选择器
    @State private var showFilePicker: Bool = false
    /// 解析错误提示
    @State private var errorMessage: String?
    /// 保存成功提示
    @State private var showSaveSuccess: Bool = false
    /// 加载完成回调
    let onLoad: (WorkflowModel?) -> Void
    /// 关闭页面回调
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部操作栏
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("选择文件", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            saveJsonToSandbox()
                        } label: {
                            Label("保存本地", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            inputText = ""
                            errorMessage = nil
                        } label: {
                            Label("清空", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    // 错误提示
                    if let errorMessage = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    // 保存成功提示
                    if showSaveSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已保存到应用文档目录")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSaveSuccess = false
                            }
                        }
                    }
                }
                .padding(.vertical, 8)

                // JSON 文本编辑区
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("在此粘贴 ComfyUI workflow.json 内容，或点击上方「选择文件」导入")
                            .foregroundColor(.secondary)
                            .padding(.top, 12)
                            .padding(.leading, 8)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(.secondarySystemBackground))
                        .opacity(inputText.isEmpty ? 0.5 : 1.0)
                }
                .padding(.horizontal)

                // 底部加载按钮
                Button {
                    loadWorkflow()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("加载工作流到画布")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("导入 JSON 工作流")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json, .text],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
        }
    }

    // MARK: - 加载工作流

    private func loadWorkflow() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "JSON 内容不能为空"
            return
        }

        guard JsonParser.isValidJson(trimmed) else {
            errorMessage = "JSON 格式不合法，请检查语法"
            return
        }

        guard let workflow = JsonParser.parseWorkflow(json: trimmed) else {
            errorMessage = "解析失败：不是有效的 ComfyUI 工作流格式（缺少 nodes 字段）"
            return
        }

        guard !workflow.nodes.isEmpty else {
            errorMessage = "工作流中没有节点"
            return
        }

        errorMessage = nil
        // 保存为上次工作流，方便主页快速打开
        WorkflowStore.saveLastWorkflow(json: trimmed, name: "导入的工作流")
        onLoad(workflow)
    }

    // MARK: - 文件导入

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // 请求访问权限（安全范围书签）
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "无法访问该文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                inputText = content
                errorMessage = nil
            } catch {
                errorMessage = "读取文件失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = "文件选择失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 本地保存

    private func saveJsonToSandbox() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "内容为空，无法保存"
            return
        }

        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "workflow-\(formatter.string(from: Date())).json"
        let fileUrl = docDir.appendingPathComponent(fileName)

        do {
            try trimmed.write(to: fileUrl, atomically: true, encoding: .utf8)
            showSaveSuccess = true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}
