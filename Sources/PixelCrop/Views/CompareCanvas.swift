//
//  CompareCanvas.swift
//  PixelCrop
//
//  对比画布。所有 UI 状态都在 AppState 中，工具栏由 RootView 提供。
//  本视图只负责画布本身：底图 + 对比图叠加 + 鼠标/滚轮交互。
//

import SwiftUI
import AppKit

struct CompareCanvas: View {
    @Environment(AppState.self) private var state
    @ObservedObject private var hold = CompareHoldState.shared

    var body: some View {
        if let base = state.baseTab {
            let compareTab = (state.activeTab?.id != base.id) ? state.activeTab : nil
            let shouldHideTop = state.compareTopHidden || state.spacePressed || hold.holdActive

            CanvasScrollHost(
                scale: Binding(
                    get: { state.compareGlobalScale },
                    set: { state.compareGlobalScale = $0 }
                ),
                offset: Binding(
                    get: { state.compareCanvasOffset },
                    set: { state.compareCanvasOffset = $0 }
                )
            ) {
                ZStack {
                    if let compare = compareTab {
                        switch state.compareStyle {
                        case .toggle:
                            ToggleStage(base: base, top: compare,
                                        topHidden: shouldHideTop)
                        case .slider:
                            SliderStage(base: base, top: compare,
                                        sliderX: Binding(
                                            get: { state.compareSliderX },
                                            set: { state.compareSliderX = $0 }
                                        ),
                                        orientation: state.compareSliderOrientation)
                        }
                    } else {
                        DisplayImageView(loaded: base.loaded)
                            .id(base.loaded.id)
                            .scaleEffect(state.compareGlobalScale)
                            .offset(x: state.compareCanvasOffset.width + state.compareDragOffset.width,
                                    y: state.compareCanvasOffset.height + state.compareDragOffset.height)
                    }
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { v in state.compareDragOffset = v.translation }
                        .onEnded { v in
                            state.compareCanvasOffset = CGSize(
                                width: state.compareCanvasOffset.width + v.translation.width,
                                height: state.compareCanvasOffset.height + v.translation.height
                            )
                            state.compareDragOffset = .zero
                        }
                )
            }
            .onAppear {
                SpaceKeyMonitor.shared.start { state.spacePressed = $0 }
            }
            .onDisappear {
                SpaceKeyMonitor.shared.stop()
            }
            .onChange(of: state.activeTabID) { _, _ in hold.holdActive = false }
        } else {
            ContentUnavailableView("无可对比的图像",
                systemImage: "rectangle.on.rectangle",
                description: Text("请打开至少一张图"))
        }
    }
}

/// 全局空格键监听器。
@MainActor
final class SpaceKeyMonitor: @unchecked Sendable {
    static let shared = SpaceKeyMonitor()
    private var monitor: Any? = nil
    private var callback: ((Bool) -> Void)? = nil

    func start(_ cb: @escaping (Bool) -> Void) {
        stop()
        callback = cb
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self,
                  event.keyCode == 49 else { return event }
            if event.type == .keyDown {
                if event.isARepeat { return nil }
                self.callback?(true)
                return nil
            } else {
                self.callback?(false)
                return nil
            }
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        callback = nil
    }
}

// MARK: - CanvasScrollHost
// NSViewRepresentable 包装整个画布内容。
// 内部用 NSHostingController host SwiftUI 内容，NSView 重写 scrollWheel。
// 缩放时以鼠标位置为锚点，调整 offset 让鼠标点保持不动。

struct CanvasScrollHost<Content: View>: NSViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    let content: Content

    init(scale: Binding<CGFloat>,
         offset: Binding<CGSize>,
         @ViewBuilder content: () -> Content) {
        self._scale = scale
        self._offset = offset
        self.content = content()
    }

    func makeNSView(context: Context) -> CanvasScrollHostView {
        let v = CanvasScrollHostView()
        v.scaleBinding = $scale
        v.offsetBinding = $offset
        v.setContent(content)
        return v
    }

    func updateNSView(_ nsView: CanvasScrollHostView, context: Context) {
        nsView.scaleBinding = $scale
        nsView.offsetBinding = $offset
        nsView.setContent(content)
    }
}

final class CanvasScrollHostView: NSView {
    var scaleBinding: Binding<CGFloat> = .constant(1.0)
    var offsetBinding: Binding<CGSize> = .constant(.zero)
    private var hostingController: NSHostingController<AnyView>? = nil
    private var lastMouseLocation: NSPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        let opts: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
    }

    func setContent<V: View>(_ content: V) {
        let anyView = AnyView(content)
        if let hc = hostingController {
            hc.rootView = anyView
        } else {
            let hc = NSHostingController(rootView: anyView)
            hostingController = hc
            let hv = hc.view
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.autoresizingMask = [.width, .height]
            addSubview(hv)
            NSLayoutConstraint.activate([
                hv.topAnchor.constraint(equalTo: topAnchor),
                hv.bottomAnchor.constraint(equalTo: bottomAnchor),
                hv.leadingAnchor.constraint(equalTo: leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }

    /// 缩放：只改 scale，不改 offset。
    /// （以鼠标为中心缩放的 offset 调整会和拖动的 offset 混用导致乱跑，暂时禁用）
    private func zoomAtAnchor(_ anchor: NSPoint, factor: CGFloat) {
        let oldScale = scaleBinding.wrappedValue
        var newScale = oldScale * factor
        newScale = max(0.1, min(8, newScale))
        scaleBinding.wrappedValue = newScale
    }

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
            // 用鼠标位置作为锚点
            let anchor = convert(event.locationInWindow, from: nil)
            zoomAtAnchor(anchor, factor: factor)
        }
    }

    override func magnify(with event: NSEvent) {
        let factor = 1 + event.magnification
        let anchor = convert(event.locationInWindow, from: nil)
        zoomAtAnchor(anchor, factor: factor)
    }
}

// MARK: - Toggle Stage

struct ToggleStage: View {
    @Environment(AppState.self) private var state
    let base: ImageTab
    let top: ImageTab
    let topHidden: Bool

    private var totalOffset: CGSize {
        CGSize(width: state.compareCanvasOffset.width + state.compareDragOffset.width,
               height: state.compareCanvasOffset.height + state.compareDragOffset.height)
    }

    var body: some View {
        ZStack {
            EditableImageView(tab: base,
                               globalScale: state.compareGlobalScale,
                               canvasOffset: totalOffset)
            EditableImageView(tab: top,
                               globalScale: state.compareGlobalScale,
                               canvasOffset: totalOffset)
                .opacity(topHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.12), value: topHidden)
        }
    }
}

// MARK: - Slider Stage

struct SliderStage: View {
    @Environment(AppState.self) private var state
    let base: ImageTab
    let top: ImageTab
    @Binding var sliderX: CGFloat
    let orientation: CompareSliderOrientation

    private var totalOffset: CGSize {
        CGSize(width: state.compareCanvasOffset.width + state.compareDragOffset.width,
               height: state.compareCanvasOffset.height + state.compareDragOffset.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                EditableImageView(tab: base,
                                   globalScale: state.compareGlobalScale,
                                   canvasOffset: totalOffset)
                    .frame(width: size.width, height: size.height)
                    .clipped()

                EditableImageView(tab: top,
                                   globalScale: state.compareGlobalScale,
                                   canvasOffset: totalOffset)
                    .frame(width: size.width, height: size.height)
                    .clipShape(
                        PartialClipShape(orientation: orientation, fraction: sliderX)
                    )

                SliderHandle(sliderX: $sliderX, orientation: orientation, size: size)
            }
        }
    }
}

// MARK: - EditableImageView
// 显示图像 + 双击进入缩放编辑模式 + 手柄缩放

struct EditableImageView: View {
    @Environment(AppState.self) private var state
    let tab: ImageTab
    let globalScale: CGFloat
    let canvasOffset: CGSize

    private var isEditing: Bool {
        state.imageEditingID == tab.id
    }

    private var imageScale: CGFloat {
        state.imageScales[tab.id] ?? 1.0
    }

    private var imageOffset: CGSize {
        state.imageOffsets[tab.id] ?? .zero
    }

    private var imageDragOffset: CGSize {
        state.imageDragOffsets[tab.id] ?? .zero
    }

    var body: some View {
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

            ZStack {
                DisplayImageView(loaded: tab.loaded)
                    .id(tab.loaded.id)
                    .frame(width: fitW, height: fitH)
                    .scaleEffect(globalScale * imageScale, anchor: .center)
                    .offset(x: canvasOffset.width + imageOffset.width + imageDragOffset.width,
                            y: canvasOffset.height + imageOffset.height + imageDragOffset.height)
                    // 双击进入/退出缩放编辑模式
                    .onTapGesture(count: 2) {
                        if state.imageEditingID == tab.id {
                            state.imageEditingID = nil
                        } else {
                            state.imageEditingID = tab.id
                        }
                    }
                    // 编辑模式下可拖动图像位置
                    .modifier(ConditionalDrag(enabled: isEditing) { v in
                        state.imageDragOffsets[tab.id] = v.translation
                    } onEnded: { v in
                        let oldOffset = state.imageOffsets[tab.id] ?? .zero
                        state.imageOffsets[tab.id] = CGSize(
                            width: oldOffset.width + v.translation.width,
                            height: oldOffset.height + v.translation.height
                        )
                        state.imageDragOffsets[tab.id] = .zero
                    })

                // 缩放编辑模式：显示边框 + 8 手柄
                if isEditing {
                    ImageHandleOverlay(tab: tab,
                                       fitW: fitW,
                                       fitH: fitH,
                                       globalScale: globalScale,
                                       canvasOffset: canvasOffset)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }
}

/// 条件性 DragGesture：enabled 为 false 时不添加 gesture。
struct ConditionalDrag: ViewModifier {
    let enabled: Bool
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: (DragGesture.Value) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                DragGesture()
                    .onChanged { v in onChanged(v) }
                    .onEnded { v in onEnded(v) }
            )
        } else {
            content
        }
    }
}

/// 浏览模式滚轮缩放 NSView。
struct ConditionalScrollZoom: NSViewRepresentable {
    let onScale: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollZoomView {
        let v = ScrollZoomView()
        v.onScale = onScale
        return v
    }

    func updateNSView(_ nsView: ScrollZoomView, context: Context) {
        nsView.onScale = onScale
    }

    static func dismantleNSView(_ nsView: ScrollZoomView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class ScrollZoomView: NSView {
    var onScale: ((CGFloat) -> Void)? = nil
    private var eventMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            installEventMonitorIfNeeded()
        }
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .magnify]
        ) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }

            if event.type == .magnify {
                self.onScale?(1 + event.magnification)
            } else {
                self.handleScroll(event)
            }
            return nil
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let delta: CGFloat
        if event.hasPreciseScrollingDeltas {
            delta = event.scrollingDeltaY
        } else {
            delta = event.deltaY
        }
        if abs(delta) > 0.001 {
            let scaledDelta = event.hasPreciseScrollingDeltas ? delta / 50 : delta
            let factor = 1 - scaledDelta * 0.1
            onScale?(factor)
        }
    }
}

/// 图像缩放手柄 overlay。
struct ImageHandleOverlay: View {
    @Environment(AppState.self) private var state
    let tab: ImageTab
    let fitW: CGFloat
    let fitH: CGFloat
    let globalScale: CGFloat
    let canvasOffset: CGSize

    private var imageScale: CGFloat {
        state.imageScales[tab.id] ?? 1.0
    }

    private var imageOffset: CGSize {
        state.imageOffsets[tab.id] ?? .zero
    }

    private var imageDragOffset: CGSize {
        state.imageDragOffsets[tab.id] ?? .zero
    }

    private var displayW: CGFloat {
        fitW * globalScale * imageScale
    }

    private var displayH: CGFloat {
        fitH * globalScale * imageScale
    }

    var body: some View {
        GeometryReader { proxy in
            let cx = proxy.size.width / 2 + canvasOffset.width + imageOffset.width + imageDragOffset.width
            let cy = proxy.size.height / 2 + canvasOffset.height + imageOffset.height + imageDragOffset.height
            let r = CGRect(x: cx - displayW / 2,
                           y: cy - displayH / 2,
                           width: displayW,
                           height: displayH)

            ZStack {
                // 高亮边框
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)

                // 8 个手柄
                ForEach([
                    ImageHandleEdge.nw, .n, .ne, .e, .se, .s, .sw, .w
                ], id: \.self) { edge in
                    HandleCircle(edge: edge, rect: r, tab: tab)
                }

                // 提示
                Text("缩放编辑中 · 双击图像退出")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor, in: Capsule())
                    .position(x: r.midX, y: r.minY - 20)
            }
        }
    }
}

enum ImageHandleEdge: String, CaseIterable {
    case nw, n, ne, e, se, s, sw, w

    func position(in r: CGRect) -> CGPoint {
        switch self {
        case .nw: return CGPoint(x: r.minX, y: r.minY)
        case .n:  return CGPoint(x: r.midX, y: r.minY)
        case .ne: return CGPoint(x: r.maxX, y: r.minY)
        case .e:  return CGPoint(x: r.maxX, y: r.midY)
        case .se: return CGPoint(x: r.maxX, y: r.maxY)
        case .s:  return CGPoint(x: r.midX, y: r.maxY)
        case .sw: return CGPoint(x: r.minX, y: r.maxY)
        case .w:  return CGPoint(x: r.minX, y: r.midY)
        }
    }
}

struct HandleCircle: View {
    let edge: ImageHandleEdge
    let rect: CGRect
    let tab: ImageTab
    @Environment(AppState.self) private var state
    @State private var dragStartScale: CGFloat = 1.0
    @State private var dragStartLocation: CGPoint = .zero

    private var pos: CGPoint {
        edge.position(in: rect)
    }

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .position(pos)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragStartScale == 1.0 && v.translation.width == 0 && v.translation.height == 0 {
                            dragStartScale = state.imageScales[tab.id] ?? 1.0
                            dragStartLocation = pos
                        }
                        // 用拖动距离作为缩放因子
                        let center = CGPoint(x: rect.midX, y: rect.midY)
                        let curDist = sqrt(pow(v.location.x - center.x, 2) + pow(v.location.y - center.y, 2))
                        let startDist = sqrt(pow(dragStartLocation.x - center.x, 2) + pow(dragStartLocation.y - center.y, 2))
                        if startDist > 0 {
                            let factor = curDist / startDist
                            var newScale = dragStartScale * factor
                            newScale = max(0.1, min(8, newScale))
                            state.imageScales[tab.id] = newScale
                        }
                    }
                    .onEnded { _ in
                        dragStartScale = 1.0
                    }
            )
    }
}

struct PartialClipShape: Shape {
    let orientation: CompareSliderOrientation
    let fraction: CGFloat
    func path(in rect: CGRect) -> Path {
        if orientation == .horizontal {
            return Path(CGRect(x: 0, y: 0,
                               width: rect.width * fraction,
                               height: rect.height))
        } else {
            return Path(CGRect(x: 0, y: 0,
                               width: rect.width,
                               height: rect.height * fraction))
        }
    }
}

struct SliderHandle: View {
    @Binding var sliderX: CGFloat
    let orientation: CompareSliderOrientation
    let size: CGSize

    var body: some View {
        ZStack {
            if orientation == .horizontal {
                Rectangle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(width: 2, height: size.height)
                    .position(x: size.width * sliderX, y: size.height / 2)
            } else {
                Rectangle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(width: size.width, height: 2)
                    .position(x: size.width / 2, y: size.height * sliderX)
            }

            Circle()
                .fill(.clear)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    Image(systemName: orientation == .horizontal
                          ? "arrow.left.and.right"
                          : "arrow.up.and.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                }
                .position(
                    x: orientation == .horizontal ? size.width * sliderX : size.width / 2,
                    y: orientation == .horizontal ? size.height / 2 : size.height * sliderX
                )
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            if orientation == .horizontal {
                                sliderX = max(0, min(1, v.location.x / size.width))
                            } else {
                                sliderX = max(0, min(1, v.location.y / size.height))
                            }
                        }
                )
        }
    }
}
