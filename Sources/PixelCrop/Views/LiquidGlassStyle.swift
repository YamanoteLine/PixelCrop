//
//  LiquidGlassStyle.swift
//  PixelCrop
//
//  macOS 26 原生 Liquid Glass 视觉组件。仅负责外观，不承载业务状态。
//

import SwiftUI

extension View {
    /// 浮层面板统一使用 macOS 26 原生 Glass，而不是 Material 模拟。
    func nativeLiquidGlassPanel(cornerRadius: CGFloat = 18) -> some View {
        glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}
