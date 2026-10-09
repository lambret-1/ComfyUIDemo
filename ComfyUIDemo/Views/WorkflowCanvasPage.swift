import SwiftUI

/// 独立画布页面：全屏展示工作流，自带导航栏与返回按钮
struct WorkflowCanvasPage: View {
    /// 工作流数据
    let workflow: WorkflowModel
    /// 关闭回调
    let onDismiss: () -> Void
    /// 环境关闭
    @Environment(\.dismiss) private var dismiss

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
                        Button {
                            // 通过通知触发重置，或使用偏好注入
                            NotificationCenter.default.post(name: .resetCanvasView, object: nil)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                }
        }
    }
}

/// 画布重置通知名
extension Notification.Name {
    static let resetCanvasView = Notification.Name("resetCanvasView")
}
