import SwiftUI

/// 主页：入口导航，提供工作流导入入口与上次工作流快速打开
struct ContentView: View {
    /// 是否展示导入页面
    @State private var showImportPage: Bool = false
    /// 是否展示画布页面
    @State private var showCanvasPage: Bool = false
    /// 当前加载的工作流
    @State private var workflow: WorkflowModel?
    /// 是否存在上次工作流
    @State private var hasLastWorkflow: Bool = false
    /// 错误提示
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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

                // 打开上次工作流按钮
                if hasLastWorkflow {
                    Button {
                        openLastWorkflow()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("打开上次工作流")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 32)
                }

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

                // 错误提示
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                hasLastWorkflow = WorkflowStore.hasLastWorkflow
            }
            .fullScreenCover(isPresented: $showImportPage) {
                JsonImportView(
                    onLoad: { model in
                        workflow = model
                        showImportPage = false
                        hasLastWorkflow = true
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
                if let workflow = workflow {
                    WorkflowCanvasPage(workflow: workflow) {
                        showCanvasPage = false
                        // 返回时刷新上次工作流状态
                        hasLastWorkflow = WorkflowStore.hasLastWorkflow
                    }
                }
            }
        }
    }

    // MARK: - 打开上次工作流

    private func openLastWorkflow() {
        guard let saved = WorkflowStore.loadLastWorkflow() else {
            errorMessage = "未找到上次工作流"
            return
        }
        guard JsonParser.isValidJson(saved.json) else {
            errorMessage = "上次工作流数据已损坏"
            return
        }
        guard let model = JsonParser.parseWorkflow(json: saved.json) else {
            errorMessage = "解析上次工作流失败"
            return
        }
        guard !model.nodes.isEmpty else {
            errorMessage = "上次工作流中没有节点"
            return
        }
        workflow = model
        errorMessage = nil
        showCanvasPage = true
    }
}
