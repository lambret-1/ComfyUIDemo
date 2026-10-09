import SwiftUI

/// 主页：入口导航，展示导入按钮与画布
struct ContentView: View {
    /// 是否展示导入页面
    @State private var showImportPage: Bool = false
    /// 当前加载的工作流
    @State private var workflow: WorkflowModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部导入按钮区
                VStack(spacing: 12) {
                    Button {
                        showImportPage = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down.on.square")
                            Text("导入 / 粘贴 JSON 工作流")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.top, 12)

                    // 工作流统计信息
                    if let workflow = workflow {
                        HStack(spacing: 16) {
                            Label("\(workflow.nodes.count) 节点", systemImage: "square.grid.2x2")
                            Label("\(workflow.links.count) 连线", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

                // 画布区域
                if let workflow = workflow {
                    WorkflowCanvasView(workflow: workflow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 空态
                    VStack(spacing: 16) {
                        Image(systemName: "circle.grid.3x3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("尚未加载工作流")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("点击上方按钮导入 ComfyUI workflow.json")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("ComfyUI 演示")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $showImportPage) {
                // 独立全屏导入页面，自带导航栈与返回
                JsonImportView(
                    onLoad: { model in
                        workflow = model
                        showImportPage = false
                    },
                    onDismiss: {
                        showImportPage = false
                    }
                )
            }
        }
    }
}
