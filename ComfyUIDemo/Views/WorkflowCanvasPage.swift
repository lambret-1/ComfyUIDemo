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
    /// 是否显示节点库菜单
    @State private var showNodeLibrary: Bool = false
    /// 保存成功提示
    @State private var showSaveSuccess: Bool = false
    /// 保存失败提示
    @State private var showSaveError: Bool = false
    /// 当前选中的模板ID
    @State private var selectedTemplateId: String?
    /// 模板加载成功提示
    @State private var showTemplateSuccess: Bool = false
    /// 模板加载失败提示
    @State private var showTemplateError: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 模板标签栏（画布上方入口）
                TemplateTabBar(
                    selectedTemplateId: $selectedTemplateId,
                    onSelect: { template in
                        loadTemplate(template)
                    }
                )

                // 画布区域（缩减一行高度容纳标签栏）
                WorkflowCanvasView(workflow: $workflow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("工作流画布")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 12) {
                            // 返回按钮
                            Button {
                                onDismiss()
                                dismiss()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("返回")
                                }
                            }
                            // 节点库菜单按钮
                            Button {
                                showNodeLibrary = true
                            } label: {
                                Image(systemName: "plus.circle")
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
                .fullScreenCover(isPresented: $showNodeLibrary) {
                    NodeLibraryMenu(
                        onSelect: { definition in
                            showNodeLibrary = false
                            addNode(definition)
                        },
                        onDismiss: {
                            showNodeLibrary = false
                        }
                    )
                }
                .overlay(alignment: .top) {
                    if showSaveSuccess {
                        saveToast(message: "已保存到本地", color: .green)
                    }
                    if showSaveError {
                        saveToast(message: "保存失败", color: .red)
                    }
                    if showTemplateSuccess {
                        saveToast(message: "模板已加载", color: .blue)
                    }
                    if showTemplateError {
                        saveToast(message: "模板加载失败", color: .red)
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

    // MARK: - 加载模板

    private func loadTemplate(_ template: WorkflowTemplate) {
        // 后台线程读取文件+解码JSON，避免主线程阻塞
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = template.loadWorkflow()
            DispatchQueue.main.async {
                guard let loaded = loaded else {
                    showTemplateError = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showTemplateError = false
                    }
                    return
                }
                workflow = loaded
                // 延迟一帧再重置视角，确保workflow已渲染到画布
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .resetCanvasView, object: nil)
                }
                showTemplateSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showTemplateSuccess = false
                }
            }
        }
    }

    // MARK: - 添加节点

    private func addNode(_ definition: NodeDefinition) {
        // 生成唯一节点ID
        let newId = (workflow.nodes.map { $0.id }.max() ?? 0) + 1

        // 计算新节点位置：放在现有节点的右下方，避免重叠
        let maxX = workflow.nodes.map { $0.position.x + $0.nodeSize.width }.max() ?? 100
        let maxY = workflow.nodes.map { $0.position.y }.max() ?? 100
        let position = CGPoint(x: maxX + 50, y: maxY + 50)

        // 根据节点定义创建NodeModel
        let newNode = definition.createNodeModel(id: newId, position: position)

        // 添加到工作流
        workflow.nodes.append(newNode)
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
