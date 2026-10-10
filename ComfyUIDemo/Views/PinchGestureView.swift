import SwiftUI

// MARK: - 双指缩放手势识别器（UIKit 封装）

/// 基于 UIPinchGestureRecognizer 的双指缩放手势，提供缩放比例和双指中心点
/// SwiftUI 原生 MagnificationGesture 仅提供 CGFloat 缩放比例，不提供手势中心点，
/// 因此用 UIKit 封装以获取双指中心，实现以手指为锚点的自然缩放。
/// 仅单指时转发触摸事件给下方 SwiftUI DragGesture，双指时不转发避免冲突。
struct PinchGestureView: UIViewRepresentable {
    /// 缩放进行中回调：scale 为从手势开始的累积缩放比例，center 为双指中心点（视图坐标）
    var onPinchChanged: (CGFloat, CGPoint) -> Void
    /// 缩放结束回调
    var onPinchEnded: () -> Void

    func makeUIView(context: Context) -> PinchRecognizerUIView {
        let view = PinchRecognizerUIView()
        view.onPinchChanged = onPinchChanged
        view.onPinchEnded = onPinchEnded
        return view
    }

    func updateUIView(_ uiView: PinchRecognizerUIView, context: Context) {
        uiView.onPinchChanged = onPinchChanged
        uiView.onPinchEnded = onPinchEnded
    }

    // MARK: - 底层 UIView：转发触摸事件 + 捏合手势识别

    final class PinchRecognizerUIView: UIView {
        var onPinchChanged: (CGFloat, CGPoint) -> Void = { _, _ in }
        var onPinchEnded: () -> Void = {}
        /// 当前活跃触摸点数量
        private var activeTouchCount: Int = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            addGestureRecognizer(pinch)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - 触摸事件转发：仅单指时转发给下方 SwiftUI，双指时不转发避免缩放与拖动冲突

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            activeTouchCount += touches.count
            if activeTouchCount <= 1 {
                next?.touchesBegan(touches, with: event)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            if activeTouchCount <= 1 {
                next?.touchesMoved(touches, with: event)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            activeTouchCount = max(0, activeTouchCount - touches.count)
            if activeTouchCount <= 1 {
                next?.touchesEnded(touches, with: event)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            activeTouchCount = max(0, activeTouchCount - touches.count)
            if activeTouchCount <= 1 {
                next?.touchesCancelled(touches, with: event)
            }
        }

        // MARK: - 捏合手势处理

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let center = gesture.location(in: self)
            switch gesture.state {
            case .began, .changed:
                onPinchChanged(gesture.scale, center)
            case .ended, .cancelled, .failed:
                onPinchEnded()
            default:
                break
            }
        }
    }
}
