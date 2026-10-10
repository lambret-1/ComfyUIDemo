import SwiftUI

// MARK: - 双指缩放手势识别器（UIKit 封装）

/// 基于 UIPinchGestureRecognizer 的双指缩放手势，提供缩放比例和双指中心点
/// SwiftUI 原生 MagnificationGesture 仅提供 CGFloat 缩放比例，不提供手势中心点，
/// 因此用 UIKit 封装以获取双指中心，实现以手指为锚点的自然缩放。
struct PinchGestureView: UIViewRepresentable {
    /// 缩放进行中回调：scale 为从手势开始的累积缩放比例，center 为双指中心点（视图坐标）
    var onPinchChanged: (CGFloat, CGPoint) -> Void
    /// 缩放结束回调
    var onPinchEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // 不拦截单指事件，使下方 SwiftUI DragGesture 可正常响应
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - 协调器

    final class Coordinator: NSObject {
        var parent: PinchGestureView

        init(_ parent: PinchGestureView) {
            self.parent = parent
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let center = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began, .changed:
                // scale 为从手势开始到当前的累积缩放比例
                parent.onPinchChanged(gesture.scale, center)
            case .ended, .cancelled, .failed:
                parent.onPinchEnded()
            default:
                break
            }
        }
    }
}
