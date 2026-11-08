//
//  RootView.swift
//  PixelCrop
//
//  根视图。
//  - 顶部工具栏：模式 + 布局选择器（始终可见，位置固定）
//  - 主区：
//    - 无图：EmptyDropZone
//    - 剪裁模式：CropWorkspace（单图）
//    - 对比模式：CompareWorkspace（底图 + 选中的对比图）
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        mainArea
            // 顶部工具栏放在 macOS 窗口标题栏位置
            .toolbar {
                // 左侧：模式选择（始终显示）
                ToolbarItemGroup(placement: .navigation) {
                    Picker("模式", selection: Binding(
                        get: { state.mode },
                        set: { state.mode = $0 }
                    )) {
                        ForEach(WorkspaceMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .disabled(state.tabs.isEmpty)
                }

                // 中间：标题
                ToolbarItemGroup(placement: .principal) {
                    if let tab = state.activeTab {
                        Text(tab.loaded.displayName)
                            .font(.callout)
                            .lineLimit(1)
                    }
                }

                // 右侧：操作按钮
                ToolbarItemGroup(placement: .primaryAction) {
                    TopToolbarContent()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.lastError)
            .animation(.easeInOut(duration: 0.2), value: state.layout)
            .animation(.easeInOut(duration: 0.2), value: state.mode)
            .sheet(isPresented: Binding(
                get: { state.showExportSheet },
                set: { state.showExportSheet = $0 }
            )) {
                ExportSheet()
            }
            .alert("未应用的编辑", isPresented: Binding(
                get: { state.pendingConfirmation != nil },
                set: { if !$0 { state.pendingConfirmation = nil } }
            )) {
                Button("继续", role: .destructive) {
                    let action = state.pendingConfirmation?.action
                    state.pendingConfirmation = nil
                    action?()
                }
                Button("取消", role: .cancel) {
                    state.pendingConfirmation = nil
                }
            } message: {
                Text(state.pendingConfirmation?.message ?? "")
            }
            .overlay(alignment: .bottom) {
                if let err = state.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.callout)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .nativeLiquidGlassPanel(cornerRadius: 14)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            state.lastError = nil
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var mainArea: some View {
        if state.tabs.isEmpty {
            EmptyDropZone { url in state.openImage(url: url) }
        } else {
            switch state.mode {
            case .crop:
                CropWorkspace()
            case .compare:
                CompareWorkspace()
            }
        }
    }
}

/// 工具栏右侧内容。
/// 编辑模式：取消（单独胶囊）+ 应用（单独蓝色胶囊）+ 撤销/重做/恢复/新增（共享长胶囊）
/// 浏览模式：撤销/重做/导出 + 恢复/新增（共享长胶囊）
struct TopToolbarContent: View {
    @Environment(AppState.self) private var state

    private var isEditing: Bool {
        state.activeTab?.editingCrop != nil
    }

    var body: some View {
        if state.mode == .crop, let tab = state.activeTab {
            if tab.editingCrop != nil {
                // 编辑模式
                // 取消：单独胶囊
                Button("取消") { state.cancelEditing(tabID: tab.id) }
                    .buttonStyle(.bordered)

                // 应用：单独蓝色高亮胶囊
                Button("应用") { state.applyCrop(tabID: tab.id) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)

                // 撤销/重做 + 恢复画布：共享长胶囊
                ControlGroup {
                    Button {
                        state.undoApply(tabID: tab.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!state.canUndoApply(tab.id) || isEditing)

                    Button {
                        state.redoApply(tabID: tab.id)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!state.canRedoApply(tab.id) || isEditing)

                    Button {
                        state.cropCanvasScale = 1.0
                        state.cropCanvasOffset = .zero
                        state.cropDragOffset = .zero
                    } label: {
                        Image(systemName: "scope")
                    }
                }

                // 新增图像：单独（编辑模式变灰）
                OpenButton()
                    .disabled(isEditing)
            } else {
                // 浏览模式
                // 撤销/重做 + 导出：共享长胶囊
                ControlGroup {
                    Button {
                        state.undoApply(tabID: tab.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!state.canUndoApply(tab.id))

                    Button {
                        state.redoApply(tabID: tab.id)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!state.canRedoApply(tab.id))
                }

                ExportButton()

                // 恢复画布 + 新增：共享长胶囊
                ControlGroup {
                    Button {
                        state.cropCanvasScale = 1.0
                        state.cropCanvasOffset = .zero
                        state.cropDragOffset = .zero
                    } label: {
                        Image(systemName: "scope")
                    }
                    .disabled(state.tabs.isEmpty)

                    OpenButton()
                }
            }
        }

        if state.mode == .compare {
            Picker("布局", selection: Binding(
                get: { state.layout },
                set: { state.layout = $0 }
            )) {
                ForEach(WindowLayout.allCases, id: \.self) { l in
                    Text(l.rawValue).tag(l)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            .disabled(state.tabs.count < 2)

            Picker("对比方式", selection: Binding(
                get: { state.compareStyle },
                set: { state.compareStyle = $0 }
            )) {
                ForEach(CompareStyle.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(state.activeTab?.id == state.baseTabID || state.tabs.count < 2)

            if state.compareStyle == .slider {
                Picker("分隔", selection: Binding(
                    get: { state.compareSliderOrientation },
                    set: { state.compareSliderOrientation = $0 }
                )) {
                    ForEach(CompareSliderOrientation.allCases, id: \.self) { o in
                        Text(o.rawValue).tag(o)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
            }

            if state.compareStyle == .toggle {
                Button {
                    state.compareTopHidden.toggle()
                } label: {
                    Image(systemName: state.compareTopHidden ? "eye.slash" : "eye")
                }
                .disabled(state.activeTab?.id == state.baseTabID)
                .help("切换上层显示（也可按住空格）")
            }

            // 恢复画布 + 新增：共享长胶囊
            ControlGroup {
                Button {
                    state.compareGlobalScale = 1.0
                    state.compareCanvasOffset = .zero
                    state.compareDragOffset = .zero
                } label: {
                    Image(systemName: "scope")
                }
                .disabled(state.tabs.isEmpty)

                OpenButton()
            }
        }
    }
}

// MARK: - 空状态拖放区

struct EmptyDropZone: View {
    var onOpen: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 8) {
                Text("把图像拖到这里")
                    .font(.title2.weight(.semibold))
                Text("或使用菜单「文件 → 打开图像…」(⌘O)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("第一张图将作为底图，后续每张可加入对比")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(["JPEG", "PNG", "HEIC", "WebP"], id: \.self) { fmt in
                        Text(fmt)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .glassEffect(.regular, in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], delegate: ImageDropDelegate(onOpen: onOpen))
        .background {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: .init(lineWidth: 1.5, dash: [8, 6]))
                .foregroundStyle(.quaternary)
                .padding(40)
        }
    }
}

struct ImageDropDelegate: DropDelegate {
    let onOpen: (URL) -> Void

    func performDrop(info: DropInfo) -> Bool {
        let items = info.itemProviders(for: [.fileURL])
        guard !items.isEmpty else { return false }
        for item in items {
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in onOpen(url) }
                }
            }
        }
        return true
    }
}

// MARK: - 顶部打开按钮

struct OpenButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = ImageFormat.openableTypes
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                for url in panel.urls {
                    state.openImage(url: url)
                }
            }
        } label: {
            Label("打开图像", systemImage: "plus.circle.fill")
        }
    }
}

// MARK: - 导出按钮

struct ExportButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            guard let id = state.activeTabID else { return }
            if state.hasUnappliedEdit() {
                state.pendingConfirmation = PendingAction(
                    message: "当前图像有未应用的剪裁编辑。导出将只包含已应用的部分，是否继续？",
                    action: { [weak state] in
                        state?.pendingExportTabID = id
                        state?.showExportSheet = true
                    }
                )
                return
            }
            state.pendingExportTabID = id
            state.showExportSheet = true
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
        .disabled(state.activeTabID == nil)
    }
}
