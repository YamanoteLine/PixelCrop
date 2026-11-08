//
//  CropRect.swift
//  PixelCrop
//
//  剪裁选框模型。始终在「原图像素坐标系」里工作，渲染时再换算到视图坐标。
//  这样窗口缩放、缩放都不会影响剪裁精度。
//

import Foundation
import CoreGraphics

/// 剪裁矩形。`unit` 归一化坐标 (0~1) 相对原图。
/// y=0 在**顶部**（与 CGImage.cropping 坐标系一致）。
struct CropRect: Equatable, Sendable {
    var unitX: CGFloat
    var unitY: CGFloat
    var unitW: CGFloat
    var unitH: CGFloat

    init(unitX: CGFloat = 0.1, unitY: CGFloat = 0.1,
         unitW: CGFloat = 0.8, unitH: CGFloat = 0.8) {
        self.unitX = unitX
        self.unitY = unitY
        self.unitW = unitW
        self.unitH = unitH
    }

    /// 转为原图像素坐标的 CGRect（y=0 在顶部，与 CGImage.cropping 一致）。
    func pixelRect(imageSize: CGSize) -> CGRect {
        CGRect(x: unitX * imageSize.width,
               y: unitY * imageSize.height,
               width: unitW * imageSize.width,
               height: unitH * imageSize.height)
    }

    /// 当前选框在原图像素下的宽高。
    func pixelSize(imageSize: CGSize) -> CGSize {
        CGSize(width: unitW * imageSize.width,
               height: unitH * imageSize.height)
    }

    /// 当前选框的 MP（保留 1 位小数）。
    func megapixels(imageSize: CGSize) -> Double {
        let s = pixelSize(imageSize: imageSize)
        return PixelCalculator.megapixels(width: s.width, height: s.height)
    }

    /// 当前选框的实际宽高比（用于推断「最接近的预设比例」）。
    func aspectRatio(imageSize: CGSize) -> CGFloat {
        let s = pixelSize(imageSize: imageSize)
        guard s.height > 0 else { return 1 }
        return s.width / s.height
    }
}

/// 剪裁模式：固定比例 vs 自由比例。
enum CropMode: String, CaseIterable, Sendable {
    case freeform = "自由"
    case locked   = "锁定比例"
}
