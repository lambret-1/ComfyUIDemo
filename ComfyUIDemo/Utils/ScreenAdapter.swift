import SwiftUI

/// 屏幕适配工具：基于 iPhone 8 Plus 基准宽度做等比缩放
enum ScreenAdapter {
    /// 屏幕宽度
    static var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }
    /// 屏幕高度
    static var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }
    /// 基准宽度（iPhone 8 Plus 逻辑分辨率 414pt）
    private static let baseWidth: CGFloat = 414

    /// 按屏幕宽度比例缩放数值
    static func scale(_ value: CGFloat) -> CGFloat {
        value * (screenWidth / baseWidth)
    }

    /// 按屏幕宽度比例缩放字体
    static func fontScale(_ value: CGFloat) -> CGFloat {
        scale(value)
    }
}
