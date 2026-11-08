//
//  ExportSheet.swift
//  PixelCrop
//
//  导出面板：格式 + 质量 + 缩小尺寸 + 文件名预览。
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(AppState.self) private var state
    @State private var format: ImageFormat = .jpeg
    @State private var quality: CGFloat = 0.85
    @State private var scaleEnabled: Bool = false
    /// 缩小比例，0.05~1.0（最低 5%），step 0.05 保证吸附点间距均等。
    @State private var scaleValue: CGFloat = 0.5
    @State private var exportError: String? = nil

    private var scale: CGFloat {
        scaleEnabled ? scaleValue : 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("导出").font(.title2.weight(.semibold))

            // 格式
            HStack {
                Text("格式").foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                Picker("格式", selection: $format) {
                    ForEach(ImageFormat.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                .onChange(of: format) { _, new in
                    quality = new.defaultQuality
                }
            }

            // 质量（PNG 时占位保持布局尺寸和高度）
            HStack {
                Text("质量").foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                if format.supportsQuality {
                    Slider(value: $quality, in: 0.05...1.0, step: 0.05)
                        .frame(width: 220)
                    Text(String(format: "%.0f%%", quality * 100))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                } else {
                    Text("无损格式")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 220 + 56, alignment: .center)
                }
            }
            .frame(height: 24)  // 固定高度，避免 PNG 时缩小

            Divider()

            // 尺寸缩小（Toggle 固定宽度避免换行）
            HStack {
                Toggle(isOn: $scaleEnabled) {
                    Text("缩小尺寸")
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(width: 60, alignment: .leading)

                Spacer()

                if scaleEnabled {
                    // 范围 0.0...1.0（5% 不顶到最左，最左=0%），step 0.05 保证吸附点 5/10/15...
                    // set 时 clamp 到 ≥0.05，不能低于 5%
                    Slider(value: Binding(
                        get: { scaleValue },
                        set: { newVal in
                            scaleValue = max(0.05, min(1.0, newVal))
                        }
                    ), in: 0.0...1.0, step: 0.05)
                    .frame(width: 220)
                    Text(String(format: "%.0f%%", scaleValue * 100))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                } else {
                    // 未勾选：滑块置灰不可交互
                    Slider(value: .constant(scaleValue), in: 0.0...1.0, step: 0.05)
                        .frame(width: 220)
                        .disabled(true)
                    Text("—")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Divider()

            // 输出预览
            if let id = state.pendingExportTabID,
               let tab = state.tabs.first(where: { $0.id == id }) {
                let origSize = tab.loaded.displaySize
                let outW = Int(origSize.width * scale)
                let outH = Int(origSize.height * scale)
                let name = ImageExporter.suggestedFilename(
                    originalName: tab.loaded.displayName,
                    format: format,
                    imageSize: origSize,
                    scale: scale
                )
                InfoRow(label: "文件名", value: name)
                if scaleEnabled {
                    InfoRow(label: "原尺寸",
                            value: "\(Int(origSize.width)) × \(Int(origSize.height))")
                    InfoRow(label: "输出尺寸",
                            value: "\(outW) × \(outH)")
                    InfoRow(label: "总像素",
                            value: PixelCalculator.megapixels(width: outW, height: outH).mpDisplay)
                } else {
                    InfoRow(label: "原尺寸",
                            value: "\(Int(origSize.width)) × \(Int(origSize.height))")
                    InfoRow(label: "输出尺寸", value: "—")
                    InfoRow(label: "总像素",
                            value: PixelCalculator.megapixels(width: Int(origSize.width),
                                                              height: Int(origSize.height)).mpDisplay)
                }
            }

            if let err = exportError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("取消") {
                    state.showExportSheet = false
                    state.pendingExportTabID = nil
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
                Button("选择位置并导出…") { runSavePanel() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .leading)
        // 设最小高度避免内容变化时 sheet 缩小，防止关闭时闪烁
        .frame(minHeight: 380, alignment: .top)
        .nativeLiquidGlassPanel(cornerRadius: 24)
    }

    @MainActor
    private func runSavePanel() {
        guard let id = state.pendingExportTabID,
              let tab = state.tabs.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = ImageExporter.suggestedFilename(
            originalName: tab.loaded.displayName,
            format: format,
            imageSize: tab.loaded.displaySize,
            scale: scale
        )
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            handleSave(url: url, tab: tab)
        }
    }

    private func handleSave(url: URL, tab: ImageTab) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let opts = ExportOptions(format: format,
                                     quality: quality,
                                     scale: scale)
            try ImageExporter.export(tab.loaded,
                                     options: opts,
                                     to: url)
            state.showExportSheet = false
            state.pendingExportTabID = nil
        } catch {
            exportError = "导出失败：\(error.localizedDescription)\n格式：\(format.displayName)\n目标：\(url.path)"
        }
    }
}
