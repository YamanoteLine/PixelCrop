//
//  CropInspector.swift
//  PixelCrop
//
//  剪裁模式右侧栏：
//  1. 当前图像信息 + 选框信息（顶部叠加）
//  2. 比例预设（单列从宽到窄，1:1 顶）+ 自由比例常显
//

import SwiftUI

struct CropInspector: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let tab = state.activeTab {
            VStack(alignment: .leading, spacing: 12) {
                // —— 段 1：图像信息 + 选框信息 ——
                VStack(spacing: 8) {
                    InfoCard(
                        title: "当前图像",
                        highlight: tab.editingCrop == nil
                    ) {
                        let imgSize = tab.loaded.displaySize
                        let mp = PixelCalculator.megapixels(width: Int(imgSize.width),
                                                            height: Int(imgSize.height))
                        InfoRow(label: "总像素", value: mp.mpDisplay)
                        InfoRow(label: "尺寸", value: "\(Int(imgSize.width)) × \(Int(imgSize.height))")
                    }

                    InfoCard(
                        title: "选框信息",
                        highlight: tab.editingCrop != nil
                    ) {
                        if let editing = tab.editingCrop {
                            let imgSize = tab.loaded.displaySize
                            let mp = editing.megapixels(imageSize: imgSize)
                            let size = editing.pixelSize(imageSize: imgSize)
                            let ratio = editing.aspectRatio(imageSize: imgSize)
                            InfoRow(label: "总像素", value: mp.mpDisplay)
                            InfoRow(label: "尺寸", value: "\(Int(size.width)) × \(Int(size.height))")
                            InfoRow(label: "比例", value: ratio.formattedRatio)
                        } else {
                            InfoRow(label: "总像素", value: "—")
                            InfoRow(label: "尺寸", value: "—")
                            InfoRow(label: "比例", value: "—")
                        }
                    }
                }

                // —— 段 2：比例预设（单列）——
                InfoCard(title: "比例预设") {
                    GlassEffectContainer(spacing: 6) {
                        VStack(spacing: 6) {
                            ForEach(CropRatio.presets) { ratio in
                                RatioPresetButton(
                                    ratio: ratio,
                                    isSelected: tab.lockedRatio == ratio
                                ) {
                                    state.lock(to: ratio, tabID: tab.id)
                                }
                            }
                            // 自由比例常显，样式和预设一致
                            RatioPresetButton(
                                ratio: CropRatio(id: "free", displayName: "自由", width: 0, height: 0),
                                isSelected: tab.editingCrop != nil && tab.cropMode == .freeform
                            ) {
                                state.unlock(tabID: tab.id)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 子组件

struct InfoCard<Content: View>: View {
    let title: String
    var highlight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if highlight {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlight
                      ? Color.accentColor.opacity(0.08)
                      : Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(highlight
                              ? Color.accentColor.opacity(0.3)
                              : Color.clear,
                              lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

/// 比例预设按钮（单列）。
struct RatioPresetButton: View {
    let ratio: CropRatio
    let isSelected: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if isSelected {
            button
                .buttonStyle(.glassProminent)
        } else {
            button
                .buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RatioPresetIcon(ratio: ratio)

                Text(ratio.displayName)
                    .font(.callout.weight(.medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
    }
}

/// 按真实宽高比绘制预设轮廓，便于快速区分横版、方形和竖版。
private struct RatioPresetIcon: View {
    let ratio: CropRatio

    private var isFreeform: Bool {
        ratio.width <= 0 || ratio.height <= 0
    }

    private var fittedSize: CGSize {
        guard !isFreeform else { return CGSize(width: 21, height: 17) }
        let maxSize = CGSize(width: 26, height: 18)
        let scale = min(
            maxSize.width / CGFloat(ratio.width),
            maxSize.height / CGFloat(ratio.height)
        )
        return CGSize(width: CGFloat(ratio.width) * scale,
                      height: CGFloat(ratio.height) * scale)
    }

    var body: some View {
        ZStack {
            if isFreeform {
                Image(systemName: "crop")
                    .font(.system(size: 17, weight: .medium))
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(lineWidth: 1.5)
                    .frame(width: fittedSize.width, height: fittedSize.height)
            }
        }
        .frame(width: 28, height: 20)
        .accessibilityHidden(true)
    }
}
