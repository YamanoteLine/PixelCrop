//
//  CropCanvas.swift
//  PixelCrop
//
//  剪裁画布：
//  - 浏览模式：只显示图像
//  - 编辑模式：图像 + 半透明蒙版 + PS 风格选框 + 顶部应用/取消条
//  - 滚轮缩放画布；选框跟随同步缩放
//  - 鼠标光标根据位置变化：选框外/内/手柄上
//

import SwiftUI
import AppKit

struct CropCanvas: View {
    @Environment(AppState.self) private var state
    let tabID: UUID

    var body: some View {
        if let idx = state.tabs.firstIndex(where: { $0.id == tabID }) {
            let tab = state.tabs[idx]
            let editing = tab.editingCrop

            // 不再用 CanvasScrollHost 包装，直接用 SwiftUI + GeometryReader
            // 滚轮缩放由 CropOverlayView 自己处理（重写 scrollWheel）
            GeometryReader { proxy in
                let imgSize = tab.loaded.displaySize
                let imgAspect = imgSize.width / max(1, imgSize.height)
                let canvasSize = proxy.size
                let canvasAspect = canvasSize.width / max(1, canvasSize.height)

                let fitW: CGFloat = imgAspect > canvasAspect
                    ? canvasSize.width
                    : canvasSize.height * imgAspect
                let fitH: CGFloat = imgAspect > canvasAspect
                    ? canvasSize.width / imgAspect
                    : canvasSize.height

                let effectiveOffset = CGSize(
                    width: state.cropCanvasOffset.width + state.cropDragOffset.width,
                    height: state.cropCanvasOffset.height + state.cropDragOffset.height
                )

                ZStack {
                    DisplayImageView(loaded: tab.loaded)
                        .id(tab.loaded.id)
                        .frame(width: fitW, height: fitH)
                        .scaleEffect(state.cropCanvasScale, anchor: .center)
                        .offset(effectiveOffset)

                    if editing != nil {
                        CropOverlay(
                            cropRect: Binding(
                                get: { state.tabs[idx].editingCrop ?? editing! },
                                set: { newValue in state.tabs[idx].editingCrop = newValue }
                            ),
                            cropMode: tab.cropMode,
                            lockedRatio: tab.lockedRatio,
                            willBeginEdit: { state.beginCropEdit(tabID) },
                            onApply: { state.applyCrop(tabID: tabID) },
                            onPanCanvas: { delta in
                                // delta 是窗口坐标差（y 已取反为 SwiftUI 方向）
                                // 除以 scale：offset 在 scaleEffect 之后，视觉放大 scale 倍
                                let s = state.cropCanvasScale
                                state.cropDragOffset = CGSize(
                                    width: delta.width / s,
                                    height: delta.height / s
                                )
                            },
                            onPanCanvasEnded: { delta in
                                let s = state.cropCanvasScale
                                state.cropCanvasOffset = CGSize(
                                    width: state.cropCanvasOffset.width + delta.width / s,
                                    height: state.cropCanvasOffset.height + delta.height / s
                                )
                                state.cropDragOffset = .zero
                            },
                            onScale: { factor in
                                state.cropCanvasScale = max(0.1, min(8, state.cropCanvasScale * factor))
                            }
                        )
                        .scaleEffect(state.cropCanvasScale, anchor: .center)
                        .offset(effectiveOffset)
                        .frame(width: fitW, height: fitH)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .modifier(ConditionalDrag(enabled: editing == nil) { v in
                    state.cropDragOffset = v.translation
                } onEnded: { v in
                    state.cropCanvasOffset = CGSize(
                        width: state.cropCanvasOffset.width + v.translation.width,
                        height: state.cropCanvasOffset.height + v.translation.height
                    )
                    state.cropDragOffset = .zero
                })
                // 浏览模式滚轮缩放
                .background(
                    Group {
                        if editing == nil {
                            ConditionalScrollZoom { factor in
                                state.cropCanvasScale = max(0.1, min(8, state.cropCanvasScale * factor))
                            }
                        }
                    }
                )
            }
        }
    }
}

extension CGFloat {
    /// 把宽高比格式化为 "9:16" 这样的可读形式，匹配预设。
    var formattedRatio: String {
        let target = self
        var best: CropRatio?
        var bestDiff: CGFloat = .infinity
        for r in CropRatio.presets {
            let diff = abs(r.aspectRatio - target)
            if diff < bestDiff { bestDiff = diff; best = r }
        }
        if let r = best, r.aspectRatio > 0, bestDiff / r.aspectRatio < 0.02 {
            return r.displayName
        }
        return String(format: "%.2f:1", target)
    }
}

// MARK: - CropOverlay (NSView 拖拽)

struct CropOverlay: NSViewRepresentable {
    @Binding var cropRect: CropRect
    let cropMode: CropMode
    let lockedRatio: CropRatio?
    var willBeginEdit: () -> Void
    var onApply: () -> Void = {}
    var onPanCanvas: (CGSize) -> Void = { _ in }
    var onPanCanvasEnded: (CGSize) -> Void = { _ in }
    var onScale: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> CropOverlayView {
        let v = CropOverlayView()
        v.delegate = context.coordinator
        return v
    }

    func updateNSView(_ nsView: CropOverlayView, context: Context) {
        nsView.cropRect = cropRect
        nsView.cropMode = cropMode
        nsView.lockedRatio = lockedRatio
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cropRect: $cropRect,
                    willBeginEdit: willBeginEdit,
                    onApply: onApply,
                    onPanCanvas: onPanCanvas,
                    onPanCanvasEnded: onPanCanvasEnded,
                    onScale: onScale)
    }

    final class Coordinator: NSObject, CropOverlayDelegate {
        let cropRectBinding: Binding<CropRect>
        let willBeginEdit: () -> Void
        let onApply: () -> Void
        let onPanCanvas: (CGSize) -> Void
        let onPanCanvasEnded: (CGSize) -> Void
        let onScale: (CGFloat) -> Void

        init(cropRect: Binding<CropRect>,
             willBeginEdit: @escaping () -> Void,
             onApply: @escaping () -> Void,
             onPanCanvas: @escaping (CGSize) -> Void,
             onPanCanvasEnded: @escaping (CGSize) -> Void,
             onScale: @escaping (CGFloat) -> Void) {
            self.cropRectBinding = cropRect
            self.willBeginEdit = willBeginEdit
            self.onApply = onApply
            self.onPanCanvas = onPanCanvas
            self.onPanCanvasEnded = onPanCanvasEnded
            self.onScale = onScale
        }

        func cropOverlayWillBeginEdit(_ view: CropOverlayView) {
            willBeginEdit()
        }

        func cropOverlay(_ view: CropOverlayView,
                         didChangeRect normalizedRect: CGRect) {
            cropRectBinding.wrappedValue = CropRect(
                unitX: normalizedRect.minX,
                unitY: normalizedRect.minY,
                unitW: normalizedRect.width,
                unitH: normalizedRect.height
            )
        }

        func cropOverlayDidDoubleTapBody(_ view: CropOverlayView) {
            onApply()
        }

        func cropOverlay(_ view: CropOverlayView, didPanCanvasBy delta: CGSize) {
            onPanCanvas(delta)
        }

        func cropOverlay(_ view: CropOverlayView, didEndPanCanvasWith delta: CGSize) {
            onPanCanvasEnded(delta)
        }

        func cropOverlay(_ view: CropOverlayView, didScaleBy factor: CGFloat) {
            onScale(factor)
        }
    }
}

protocol CropOverlayDelegate: AnyObject {
    func cropOverlayWillBeginEdit(_ view: CropOverlayView)
    func cropOverlay(_ view: CropOverlayView, didChangeRect normalizedRect: CGRect)
    func cropOverlayDidDoubleTapBody(_ view: CropOverlayView)
    func cropOverlay(_ view: CropOverlayView, didPanCanvasBy delta: CGSize)
    func cropOverlay(_ view: CropOverlayView, didEndPanCanvasWith delta: CGSize)
    func cropOverlay(_ view: CropOverlayView, didScaleBy factor: CGFloat)
}

extension CropOverlayDelegate {
    func cropOverlayDidDoubleTapBody(_ view: CropOverlayView) {}
    func cropOverlay(_ view: CropOverlayView, didPanCanvasBy delta: CGSize) {}
    func cropOverlay(_ view: CropOverlayView, didEndPanCanvasWith delta: CGSize) {}
    func cropOverlay(_ view: CropOverlayView, didScaleBy factor: CGFloat) {}
}

/// 自定义 NSView：画暗色蒙版 + 选框 + 8 个拖拽手柄。
/// 处理鼠标光标根据位置变化。
final class CropOverlayView: NSView {
    weak var delegate: CropOverlayDelegate?
    var cropRect: CropRect = CropRect()
    var cropMode: CropMode = .freeform
    var lockedRatio: CropRatio? = nil

    private enum Handle: Int { case nw, n, ne, e, se, s, sw, w, body, outside, canvas }

    private var draggingHandle: Handle? = nil
    private var dragStartRect: CGRect = .zero
    private var dragStartPoint: NSPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        // 安装 trackingArea 以接收 mouseMoved
        let opts: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    private func displayRectInView() -> CGRect {
        // 选框归一化坐标 y=0 在顶部，NSView isFlipped=true 也是 y=0 在顶部，直接对应。
        let r = cropRect
        let b = bounds
        return CGRect(x: r.unitX * b.width,
                      y: r.unitY * b.height,
                      width: r.unitW * b.width,
                      height: r.unitH * b.height)
    }

    private func normalized(fromViewRect vr: CGRect) -> CGRect {
        // NSView flipped（y=0 顶部）→ 归一化（y=0 顶部），不翻转。
        let b = bounds
        guard b.width > 0, b.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(x: vr.minX / b.width,
                      y: vr.minY / b.height,
                      width: vr.width / b.width,
                      height: vr.height / b.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        let sel = displayRectInView()

        // 暗色蒙版（选框外区域）
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(b)
        ctx.setBlendMode(.destinationOut)
        ctx.fill(sel)
        ctx.setBlendMode(.normal)

        // 选框外层白色细线
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(sel)

        // 选框内层 accent 线
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(sel)

        // 三等分线（虚线）
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        for i in 1...2 {
            let x = sel.minX + sel.width * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: sel.minY))
            ctx.addLine(to: CGPoint(x: x, y: sel.maxY))
            let y = sel.minY + sel.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: sel.minX, y: y))
            ctx.addLine(to: CGPoint(x: sel.maxX, y: y))
        }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // 8 个手柄
        let hs: CGFloat = 10
        for hp in handlePoints(in: sel) {
            let rect = CGRect(x: hp.x - hs/2, y: hp.y - hs/2, width: hs, height: hs)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect)
        }
    }

    private func handlePoints(in r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.maxX, y: r.maxY),
            CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.minX, y: r.midY),
        ]
    }

    /// 根据手柄返回光标。
    private func cursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .nw, .se, .ne, .sw:
            // 对角线方向用 crosshair
            return .crosshair
        case .n, .s:   return .resizeUpDown
        case .e, .w:   return .resizeLeftRight
        case .body:    return .openHand
        case .outside, .canvas: return .arrow
        }
    }

    private func handle(at p: NSPoint) -> Handle {
        let r = displayRectInView()
        let tol: CGFloat = 12
        let pts = handlePoints(in: r)
        let handles: [Handle] = [.nw, .n, .ne, .e, .se, .s, .sw, .w]
        for (i, hp) in pts.enumerated() {
            if abs(hp.x - p.x) <= tol && abs(hp.y - p.y) <= tol {
                return handles[i]
            }
        }
        if r.contains(p) { return .body }
        return .outside
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h = handle(at: p)
        cursor(for: h).set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h = handle(at: p)

        // 双击选框内 → 应用剪裁
        if event.clickCount >= 2 && h == .body {
            delegate?.cropOverlayDidDoubleTapBody(self)
            return
        }

        // 选框外：拖动画布
        if h == .outside {
            draggingHandle = .canvas
            // 用窗口坐标，不受 isFlipped 影响
            dragStartPoint = event.locationInWindow
            return
        }

        draggingHandle = h
        dragStartRect = displayRectInView()
        dragStartPoint = event.locationInWindow
        delegate?.cropOverlayWillBeginEdit(self)
        if h == .body { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let h = draggingHandle else { return }

        // 选框外拖动：用窗口坐标差计算绝对偏移
        if h == .canvas {
            let dx = event.locationInWindow.x - dragStartPoint.x
            // 窗口坐标 y 向上，SwiftUI offset y 向下，取反
            let dy = -(event.locationInWindow.y - dragStartPoint.y)
            delegate?.cropOverlay(self, didPanCanvasBy: CGSize(width: dx, height: dy))
            return
        }

        // 选框/手柄拖动：用 view 坐标
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - convert(dragStartPoint, from: nil).x
        let dy = p.y - convert(dragStartPoint, from: nil).y
        var r = dragStartRect
        let minSize: CGFloat = 20
        let aspect = lockedRatio?.aspectRatio
        let locked = cropMode == .locked

        switch h {
        case .nw:
            r.origin.x += dx; r.size.width -= dx
            r.origin.y += dy; r.size.height -= dy
            if locked, let a = aspect {
                let newH = r.width / a
                r.origin.y = r.maxY - newH
                r.size.height = newH
            }
        case .n:
            r.origin.y += dy; r.size.height -= dy
            if locked, let a = aspect {
                let newW = r.height * a
                r.origin.x = r.midX - newW / 2
                r.size.width = newW
            }
        case .ne:
            r.size.width += dx
            r.origin.y += dy; r.size.height -= dy
            if locked, let a = aspect {
                let newH = r.width / a
                r.origin.y = r.maxY - newH
                r.size.height = newH
            }
        case .e:
            r.size.width += dx
            if locked, let a = aspect {
                let newH = r.width / a
                r.origin.y = r.midY - newH / 2
                r.size.height = newH
            }
        case .se:
            r.size.width += dx
            r.size.height += dy
            if locked, let a = aspect {
                let newH = r.width / a
                r.size.height = newH
            }
        case .s:
            r.size.height += dy
            if locked, let a = aspect {
                let newW = r.height * a
                r.origin.x = r.midX - newW / 2
                r.size.width = newW
            }
        case .sw:
            r.origin.x += dx; r.size.width -= dx
            r.size.height += dy
            if locked, let a = aspect {
                let newH = r.width / a
                r.size.height = newH
            }
        case .w:
            r.origin.x += dx; r.size.width -= dx
            if locked, let a = aspect {
                let newH = r.width / a
                r.origin.y = r.midY - newH / 2
                r.size.height = newH
            }
        case .body:
            r.origin.x += dx
            r.origin.y += dy
        case .outside, .canvas:
            break
        }

        if r.width < minSize {
            if h == .body { r.origin.x = dragStartRect.origin.x + dx }
            r.size.width = minSize
        }
        if r.height < minSize {
            if h == .body { r.origin.y = dragStartRect.origin.y + dy }
            r.size.height = minSize
        }

        r = r.intersection(bounds)
        if r.isNull { r = dragStartRect }

        let norm = normalized(fromViewRect: r)
        delegate?.cropOverlay(self, didChangeRect: norm)
    }

    override func mouseUp(with event: NSEvent) {
        // 如果是画布拖动结束，通知 delegate 合并偏移
        if draggingHandle == .canvas {
            let dx = event.locationInWindow.x - dragStartPoint.x
            let dy = -(event.locationInWindow.y - dragStartPoint.y)
            delegate?.cropOverlay(self, didEndPanCanvasWith: CGSize(width: dx, height: dy))
        }
        draggingHandle = nil
        NSCursor.arrow.set()
    }

    // 滚轮缩放：直接处理，调用 delegate
    override func scrollWheel(with event: NSEvent) {
        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = event.scrollingDeltaY
        } else {
            delta = event.deltaY
        }
        if abs(delta) > 0.001 {
            let scaledDelta = event.hasPreciseScrollingDeltas ? delta / 50 : delta
            let factor = 1 - scaledDelta * 0.1
            delegate?.cropOverlay(self, didScaleBy: factor)
        }
    }

    // 触控板捏合缩放
    override func magnify(with event: NSEvent) {
        let factor = 1 + event.magnification
        delegate?.cropOverlay(self, didScaleBy: factor)
    }
}
