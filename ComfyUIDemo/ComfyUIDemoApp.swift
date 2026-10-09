import SwiftUI

/// 应用入口
@main
struct ComfyUIDemoApp: App {
    init() {
        // 预加载节点数据库（从Bundle JSON读取）
        NodeDatabase.loadIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
