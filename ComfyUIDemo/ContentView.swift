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

    // 更新相关状态
    @StateObject private var updateManager = AppUpdateManager.shared
    @State private var showUpdateAlert: Bool = false
    @State private var showNoUpdateAlert: Bool = false
    @State private var showDownloadProgress: Bool = false
    @State private var showCheckError: Bool = false
    @State private var downloadedFileURL: URL?

    /// 应用版本号（从Info.plist读取）
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
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

                    // 新增空白工作流按钮
                    Button {
                        createBlankWorkflow()
                    } label: {
                        HStack {
                            Image(systemName: "plus.square.dashed")
                            Text("新增空白工作流")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
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

                    // 底部版本号（双击检查更新）
                    Text("版本 \(appVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 16)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            checkForUpdates()
                        }
                }

                // 下载进度遮罩
                if showDownloadProgress {
                    downloadProgressView
                        .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                hasLastWorkflow = WorkflowStore.hasLastWorkflow
            }
            .alert("发现新版本", isPresented: $showUpdateAlert) {
                Button("立即更新") {
                    startDownload()
                }
                Button("稍后再说", role: .cancel) {}
            } message: {
                if let latest = updateManager.latestVersion {
                    Text("当前版本 v\(appVersion)\n最新版本 v\(latest)\n\n是否下载更新？")
                }
            }
            .alert("已是最新版本", isPresented: $showNoUpdateAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("当前版本 v\(appVersion) 已是最新版本")
            }
            .alert("检查更新失败", isPresented: $showCheckError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(updateManager.downloadError ?? "网络连接失败，请稍后重试")
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
                        hasLastWorkflow = WorkflowStore.hasLastWorkflow
                    }
                }
            }
        }
    }

    // MARK: - 下载进度视图

    private var downloadProgressView: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if updateManager.isDownloading {
                    Text("正在下载更新...")
                        .font(.headline)

                    ProgressView(value: updateManager.downloadProgress) {
                        Text(String(format: "%.0f%%", updateManager.downloadProgress * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 240)

                    if let error = updateManager.downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else {
                    Text("下载完成")
                        .font(.headline)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("即将打开分享面板，请选择 TrollStore 安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(32)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }

    // MARK: - 检查更新

    private func checkForUpdates() {
        guard !updateManager.isChecking, !updateManager.isDownloading else { return }
        updateManager.checkForUpdate(currentVersion: appVersion) { hasUpdate, latestVersion in
            if hasUpdate {
                showUpdateAlert = true
            } else if latestVersion != nil {
                showNoUpdateAlert = true
            } else {
                updateManager.downloadError = "无法获取版本信息"
                showCheckError = true
            }
        }
    }

    // MARK: - 开始下载

    private func startDownload() {
        showUpdateAlert = false
        showDownloadProgress = true
        updateManager.downloadLatestIPA { fileURL in
            if let fileURL = fileURL {
                downloadedFileURL = fileURL
                // 延迟一秒后分享，让用户看到下载完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    shareDownloadedFile(fileURL)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showDownloadProgress = false
                    showCheckError = true
                }
            }
        }
    }

    // MARK: - 分享安装包

    private func shareDownloadedFile(_ fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            showDownloadProgress = false
            return
        }
        showDownloadProgress = false
        updateManager.shareIPA(fileURL, from: rootVC)
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

    // MARK: - 创建空白工作流

    private func createBlankWorkflow() {
        let blank = WorkflowModel(nodes: [], links: [], groups: [])
        workflow = blank
        errorMessage = nil
        showCanvasPage = true
    }
}
