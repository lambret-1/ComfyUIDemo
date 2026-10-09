import SwiftUI

/// 独立画布页面：全屏展示工作流，自带导航栏、返回、搜索、保存按钮
struct WorkflowCanvasPage: View {
    /// 工作流数据（可编辑，支持参数修改后保存）
    @State var workflow: WorkflowModel
    /// 关闭回调
    let onDismiss: () -> Void
    /// 环境关闭
    @Environment(\.dismiss) private var dismiss
    /// 是否显示搜索页面
    @State private var showSearch: Bool = false
    /// 保存成功提示
    @State private var showSaveSuccess: Bool = false
    /// 保存失败提示
    @State private var showSaveError: Bool = false

    var body: some View {
        NavigationStack {
            WorkflowCanvasView(workflow: $workflow)
                .navigationTitle("工作流画布")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            onDismiss()
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("返回")
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            // 保存按钮
                            Button {
                                saveWorkflow()
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            // 搜索按钮
                            Button {
                                showSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            // 重置视角按钮
                            Button {
                                NotificationCenter.default.post(name: .resetCanvasView, object: nil)
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $showSearch) {
                    NodeSearchPage(workflow: workflow) { nodeId in
                        showSearch = false
                        NotificationCenter.default.post(name: .focusNode, object: nodeId)
                    }
                }
                .overlay(alignment: .top) {
                    if showSaveSuccess {
                        saveToast(message: "已保存到本地", color: .green)
                    }
                    if showSaveError {
                        saveToast(message: "保存失败", color: .red)
                    }
                }
        }
    }

    // MARK: - 保存工作流

    private func saveWorkflow() {
        let success = WorkflowStore.saveWorkflowToDocuments(workflow, name: "workflow-\(workflow.nodes.count)nodes.json")
        if success {
            showSaveSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSaveSuccess = false
            }
        } else {
            showSaveError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSaveError = false
            }
        }
    }

    private func saveToast(message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: color == .green ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(color)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.top, 8)
    }
}

/// 画布通知名
extension Notification.Name {
    static let resetCanvasView = Notification.Name("resetCanvasView")
    static let focusNode = Notification.Name("focusNode")
}
