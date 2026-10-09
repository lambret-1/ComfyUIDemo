import SwiftUI

/// 主页：入口导航，提供工作流导入入口
struct ContentView: View {
    /// 是否展示导入页面
    @State private var showImportPage: Bool = false
    /// 是否展示画布页面
    @State private var showCanvasPage: Bool = false
    /// 当前加载的工作流
    @State private var workflow: WorkflowModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 应用图标与标题
                VStack(spacing: 12) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.teal)
                    Text("ComfyUI 演示")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("工作流可视化查看器")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 导入按钮
                Button {
                    showImportPage = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.on.square")
                        Text("导入 / 粘贴 JSON 工作流")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)

                // 已加载工作流入口
                if workflow != nil {
                    Button {
                        showCanvasPage = true
                    } label: {
                        HStack {
                            Image(systemName: "arrowtriangle.right.circle.fill")
                            Text("打开当前工作流")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 32)
                }

                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showImportPage) {
                // 独立全屏导入页面
                JsonImportView(
                    onLoad: { model in
                        workflow = model
                        showImportPage = false
                        if model != nil {
                            showCanvasPage = true
                        }
                    },
                    onDismiss: {
                        showImportPage = false
                    }
                )
            }
            .fullScreenCover(isPresented: $showCanvasPage) {
                // 独立全屏画布页面
                if let workflow = workflow {
                    WorkflowCanvasPage(workflow: workflow) {
                        showCanvasPage = false
                    }
                }
            }
        }
    }
}
