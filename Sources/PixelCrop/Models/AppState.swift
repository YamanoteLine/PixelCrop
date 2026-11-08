//
//  AppState.swift
//  PixelCrop
//
//  全局可观察状态。
//
//  语义：
//  - tabs[0] 永远是底图（不可关闭，除非删完）
//  - 剪裁模式：只看 activeTab 这一张，无侧栏无标签页
//  - 对比模式：显示侧栏/标签页，选择 activeTab 即"把这张图和底图对比"
//    （若 activeTab 是底图本身，则只显示底图）
//

import Foundation
import SwiftUI
import Observation
import ImageIO
import UniformTypeIdentifiers

/// 单个被打开的图像。
struct ImageTab: Identifiable, Equatable {
    let id = UUID()
    var loaded: LoadedImage
    /// 编辑中的剪裁框。nil 表示当前未在编辑模式。
    var editingCrop: CropRect? = nil
    var cropMode: CropMode = .freeform
    var lockedRatio: CropRatio? = nil
    /// 临时文件路径（应用过剪裁的图来源），关闭时需清理。
    var tempURL: URL? = nil

    /// 应用层历史栈：每次 applyCrop 前保存应用前的 LoadedImage 快照。
    var appliedUndoStack: [LoadedImage] = []
    var appliedRedoStack: [LoadedImage] = []

    static func == (lhs: ImageTab, rhs: ImageTab) -> Bool { lhs.id == rhs.id }
}

/// 工作区模式。
enum WorkspaceMode: String, CaseIterable, Sendable {
    case crop    = "剪裁"
    case compare = "对比"
}

/// 窗口布局（仅对比模式下生效）。
enum WindowLayout: String, CaseIterable, Sendable {
    case sidebar = "侧栏"
    case tabs    = "标签页"
}

@MainActor
@Observable
final class AppState {
    // —— 窗口级 ——
    var layout: WindowLayout = .sidebar
    var mode: WorkspaceMode = .crop

    // —— 文档 ——
    var tabs: [ImageTab] = []
    var activeTabID: UUID? = nil
    /// 底图 ID。对比模式下，底图作为下层。可手动切换。
    var baseTabID: UUID? = nil

    // —— 撤销栈 ——
    var undoStacks: [UUID: UndoStack<CropRect>] = [:]

    // —— UI 反馈 ——
    var lastError: String? = nil
    var showExportSheet: Bool = false
    var pendingExportTabID: UUID? = nil

    // —— 确认对话框（导入/导出时检测到未应用的编辑）——
    /// 待确认的操作（用户点击确认后执行）。
    var pendingConfirmation: PendingAction? = nil

    // —— 对比模式 UI 状态（提升到全局，便于顶部工具栏访问）——
    var compareStyle: CompareStyle = .toggle
    var compareTopHidden: Bool = false
    var compareSliderX: CGFloat = 0.5
    var compareSliderOrientation: CompareSliderOrientation = .horizontal
    var compareGlobalScale: CGFloat = 1.0
    var compareCanvasOffset: CGSize = .zero
    var compareDragOffset: CGSize = .zero
    var spacePressed: Bool = false

    // —— 剪裁模式 UI 状态 ——
    var cropCanvasScale: CGFloat = 1.0
    var cropCanvasOffset: CGSize = .zero
    var cropDragOffset: CGSize = .zero

    // —— 对比模式图像缩放编辑 ——
    /// 当前进入"图像缩放编辑"模式的图像 ID（双击进入）。
    var imageEditingID: UUID? = nil
    /// 每张图各自的缩放（在画布整体缩放之外）。
    var imageScales: [UUID: CGFloat] = [:]
    /// 每张图各自的偏移（在画布整体偏移之外）。
    var imageOffsets: [UUID: CGSize] = [:]
    /// 拖动临时偏移（onEnded 时合并到 imageOffsets）。
    var imageDragOffsets: [UUID: CGSize] = [:]
    @ObservationIgnored
    private var _holdState: CompareHoldState? = nil

    var holdState: CompareHoldState {
        if _holdState == nil { _holdState = CompareHoldState() }
        return _holdState!
    }

    // MARK: - Derived

    /// 底图。无图返回 nil。
    var baseTab: ImageTab? {
        guard let id = baseTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    /// 当前活动的图。
    var activeTab: ImageTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var activeIndex: Int? {
        guard let id = activeTabID else { return nil }
        return tabs.firstIndex { $0.id == id }
    }

    // MARK: - 文档操作

    /// 检查当前 active tab 是否有未应用的剪裁编辑。
    func hasUnappliedEdit() -> Bool {
        guard let tab = activeTab else { return false }
        return tab.editingCrop != nil
    }

    /// 导入新图像。如果当前有未应用的编辑，弹窗确认。
    @MainActor
    func openImage(url: URL) {
        // 检查未应用编辑
        if hasUnappliedEdit() {
            pendingConfirmation = PendingAction(
                message: "当前图像有未应用的剪裁编辑。继续导入新图像将丢弃当前编辑，是否继续？",
                action: { [weak self] in
                    self?.cancelEditing(tabID: (self?.activeTabID)!)
                    self?.doOpenImage(url: url)
                }
            )
            return
        }
        doOpenImage(url: url)
    }

    @MainActor
    private func doOpenImage(url: URL) {
        do {
            let loaded = try ImageLoader.open(url)
            let tab = ImageTab(loaded: loaded)
            tabs.append(tab)
            undoStacks[tab.id] = UndoStack<CropRect>()
            // 第一张图自动设为 base
            if tabs.count == 1 {
                baseTabID = tab.id
            }
            // 自动激活新导入的图像
            activeTabID = tab.id
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 把指定图设为底图。
    @MainActor
    func setBase(tabID: UUID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        baseTabID = tabID
    }

    @MainActor
    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        // 清理临时文件
        if let temp = tabs[idx].tempURL {
            try? FileManager.default.removeItem(at: temp)
        }
        tabs.remove(at: idx)
        undoStacks.removeValue(forKey: id)

        // 重置 active
        if activeTabID == id {
            activeTabID = tabs.first?.id
        }
        // 重置 base：按顺序下一张；如果删的是最后一张，回 nil
        if baseTabID == id {
            baseTabID = tabs.first?.id
        }
    }

    // MARK: - 剪裁会话

    @MainActor
    func startEditing(tabID: UUID,
                      ratio: CropRatio? = nil,
                      megapixels mp: Double? = nil) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[idx].editingCrop == nil {
            tabs[idx].editingCrop = CropRect(unitX: 0.05, unitY: 0.05,
                                             unitW: 0.9, unitH: 0.9)
        }
        undoStacks[tabID, default: UndoStack()].commit(current: tabs[idx].editingCrop!)
        if let r = ratio { _applyRatio(r, to: &tabs[idx]) }
        if let mp = mp, mp > 0 { _resizeEditing(toMegapixels: mp, in: &tabs[idx]) }
    }

    @MainActor
    func applyCrop(tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = tabs[idx]
        guard let editing = tab.editingCrop else { return }

        let pixelRect = editing.pixelRect(imageSize: tab.loaded.displaySize)
        guard let cropped = tab.loaded.makeCroppedCGImage(rect: pixelRect) else {
            lastError = "剪裁失败"
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixelcrop-\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else {
            lastError = "无法创建临时文件"
            return
        }
        CGImageDestinationAddImage(dest, cropped, nil)
        guard CGImageDestinationFinalize(dest) else {
            lastError = "无法写入临时文件"
            return
        }

        do {
            let newLoaded = try ImageLoader.open(tempURL)
            // 保存应用前的 loaded 到 undo 栈（不删除旧 tempURL，撤销时需要）
            tabs[idx].appliedUndoStack.append(tab.loaded)
            tabs[idx].appliedRedoStack.removeAll()
            tabs[idx].loaded = newLoaded
            tabs[idx].tempURL = tempURL
            tabs[idx].editingCrop = nil
            tabs[idx].cropMode = .freeform
            tabs[idx].lockedRatio = nil
            undoStacks[tabID] = UndoStack<CropRect>()
        } catch {
            lastError = error.localizedDescription
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    /// 撤销最近一次 applyCrop：恢复到应用前的图。
    @MainActor
    func undoApply(tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let previous = tabs[idx].appliedUndoStack.popLast() else { return }
        tabs[idx].appliedRedoStack.append(tabs[idx].loaded)
        tabs[idx].loaded = previous
        tabs[idx].editingCrop = nil
        tabs[idx].cropMode = .freeform
        tabs[idx].lockedRatio = nil
    }

    /// 重做最近一次被撤销的 applyCrop。
    @MainActor
    func redoApply(tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let next = tabs[idx].appliedRedoStack.popLast() else { return }
        tabs[idx].appliedUndoStack.append(tabs[idx].loaded)
        tabs[idx].loaded = next
        tabs[idx].editingCrop = nil
        tabs[idx].cropMode = .freeform
        tabs[idx].lockedRatio = nil
    }

    /// 当前 tab 是否可撤销应用。
    func canUndoApply(_ tabID: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return false }
        return !tab.appliedUndoStack.isEmpty
    }

    /// 当前 tab 是否可重做应用。
    func canRedoApply(_ tabID: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return false }
        return !tab.appliedRedoStack.isEmpty
    }

    @MainActor
    func cancelEditing(tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].editingCrop = nil
        tabs[idx].cropMode = .freeform
        tabs[idx].lockedRatio = nil
    }

    @MainActor
    func beginCropEdit(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }),
              let editing = tab.editingCrop else { return }
        undoStacks[id, default: UndoStack()].commit(current: editing)
    }

    @MainActor
    func undo(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }),
              let editing = tab.editingCrop else { return }
        guard var stack = undoStacks[id] else { return }
        if let prev = stack.undo(current: editing) {
            if let idx = tabs.firstIndex(where: { $0.id == id }) {
                tabs[idx].editingCrop = prev
            }
        }
        undoStacks[id] = stack
    }

    @MainActor
    func redo(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }),
              let editing = tab.editingCrop else { return }
        guard var stack = undoStacks[id] else { return }
        if let next = stack.redo(current: editing) {
            if let idx = tabs.firstIndex(where: { $0.id == id }) {
                tabs[idx].editingCrop = next
            }
        }
        undoStacks[id] = stack
    }

    @MainActor
    func lock(to ratio: CropRatio, tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[idx].editingCrop == nil {
            startEditing(tabID: tabID, ratio: ratio)
            return
        }
        _applyRatio(ratio, to: &tabs[idx])
        tabs[idx].cropMode = .locked
        tabs[idx].lockedRatio = ratio
    }

    @MainActor
    func unlock(tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[idx].editingCrop == nil {
            startEditing(tabID: tabID)
            return
        }
        tabs[idx].cropMode = .freeform
        tabs[idx].lockedRatio = nil
    }

    @MainActor
    func resize(toMegapixels mp: Double, tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabs[idx].editingCrop == nil {
            startEditing(tabID: tabID, megapixels: mp)
            return
        }
        _resizeEditing(toMegapixels: mp, in: &tabs[idx])
    }

    // MARK: - Private helpers

    private func _applyRatio(_ ratio: CropRatio, to tab: inout ImageTab) {
        guard var editing = tab.editingCrop else { return }
        let imgSize = tab.loaded.displaySize
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        let aspect = ratio.aspectRatio
        let imgAspect = imgSize.width / imgSize.height

        let cur = editing.pixelRect(imageSize: imgSize)
        let cx = cur.midX
        let cy = cur.midY

        // 在原图范围内最大可容纳的该比例矩形
        var finalW: CGFloat
        var finalH: CGFloat
        if aspect > imgAspect {
            // 受宽度限制
            finalW = imgSize.width
            finalH = finalW / aspect
        } else {
            // 受高度限制
            finalH = imgSize.height
            finalW = finalH * aspect
        }

        // 让结果贴近当前选框大小：保持「最长边」长度不变
        let maxCurSide = max(cur.width, cur.height)
        if aspect >= 1 {
            finalW = min(finalW, maxCurSide)
            finalH = finalW / aspect
        } else {
            finalH = min(finalH, maxCurSide)
            finalW = finalH * aspect
        }

        // 不能超过原图
        if finalW > imgSize.width || finalH > imgSize.height {
            let s = min(imgSize.width / finalW, imgSize.height / finalH)
            finalW *= s
            finalH *= s
        }

        var newRect = CGRect(x: cx - finalW / 2,
                             y: cy - finalH / 2,
                             width: finalW,
                             height: finalH)
        newRect.origin.x = max(0, min(newRect.minX, imgSize.width - finalW))
        newRect.origin.y = max(0, min(newRect.minY, imgSize.height - finalH))
        editing.unitX = newRect.origin.x / imgSize.width
        editing.unitY = newRect.origin.y / imgSize.height
        editing.unitW = newRect.width / imgSize.width
        editing.unitH = newRect.height / imgSize.height
        tab.editingCrop = editing
        tab.cropMode = .locked
        tab.lockedRatio = ratio
    }

    private func _resizeEditing(toMegapixels mp: Double, in tab: inout ImageTab) {
        guard var editing = tab.editingCrop else { return }
        let imgSize = tab.loaded.displaySize
        let ratio: CropRatio
        if let r = tab.lockedRatio {
            ratio = r
        } else {
            let a = editing.aspectRatio(imageSize: imgSize)
            ratio = CropRatio(id: "cur", displayName: "当前",
                              width: max(1, Int(a * 1000)), height: 1000)
        }
        let (w, h) = PixelCalculator.dimensions(for: ratio, megapixels: mp)
        var finalW = CGFloat(w)
        var finalH = CGFloat(h)
        if finalW > imgSize.width || finalH > imgSize.height {
            let s = min(imgSize.width / finalW, imgSize.height / finalH)
            finalW *= s
            finalH *= s
        }
        let cur = editing.pixelRect(imageSize: imgSize)
        let cx = cur.midX
        let cy = cur.midY
        var newRect = CGRect(x: cx - finalW / 2,
                             y: cy - finalH / 2,
                             width: finalW,
                             height: finalH)
        newRect.origin.x = max(0, min(newRect.minX, imgSize.width - finalW))
        newRect.origin.y = max(0, min(newRect.minY, imgSize.height - finalH))
        editing.unitX = newRect.origin.x / imgSize.width
        editing.unitY = newRect.origin.y / imgSize.height
        editing.unitW = newRect.width / imgSize.width
        editing.unitH = newRect.height / imgSize.height
        tab.editingCrop = editing
    }
}

/// 对比模式子样式。
enum CompareStyle: String, CaseIterable, Sendable {
    case toggle = "隐藏显现"
    case slider = "拖动浮现"
}

/// 对比模式分隔线方向。
enum CompareSliderOrientation: String, CaseIterable, Sendable {
    case horizontal = "水平"
    case vertical = "垂直"
}

/// 侧栏/标签页"按住当前项"状态。
@MainActor
final class CompareHoldState: ObservableObject, @unchecked Sendable {
    static let shared = CompareHoldState()
    @Published var holdActive: Bool = false
}

/// 待确认的操作：当导入/导出时检测到未应用的编辑，弹窗让用户选择。
/// 用户确认后执行 `action`，取消则丢弃。
struct PendingAction: Identifiable {
    let id = UUID()
    let message: String
    /// 确认后执行的操作。
    let action: () -> Void
}
