import SwiftUI

// MARK: - 数组安全下标

extension Array {
    /// 安全下标访问：越界返回 nil 而非崩溃
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
