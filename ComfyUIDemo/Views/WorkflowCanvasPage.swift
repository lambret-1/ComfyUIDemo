import SwiftUI

/// 独立画布页面：全屏展示工作流，自带导航栏与返回按钮
struct WorkflowCanvasPage: View {
    /// 工作流数据
    let workflow: WorkflowModel
    /// 关闭回调
    let onDismiss: () -> Void
    /// 环境关闭
    @Environment(\.dismiss) private var dismiss
    /// 是否显示搜索页面
    @State private var showSearch: Bool = false

    var body: some View {
        NavigationStack {
            WorkflowCanvasView(workflow: workflow)
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
                        HStack(spacing: 12) {
                            Button {
                                showSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
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
        }
    }
}

/// 画布通知名
extension Notification.Name {
    static let resetCanvasView = Notification.Name("resetCanvasView")
    static let focusNode = Notification.Name("focusNode")
}
