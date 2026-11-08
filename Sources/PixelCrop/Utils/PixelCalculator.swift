//
//  PixelCalculator.swift
//  PixelCrop
//
//  像素值（MP）与比例（CropRatio）之间的双向换算。
//  设计原则：所有换算都在「全像素」域里完成，最后再 round。
//

import Foundation
import CoreGraphics

enum PixelCalculator {

    /// 一百万像素。MP 与像素之间的换算常数。
    static let pixelsPerMP: Double = 1_000_000

    /// 把宽高（像素）换算为 MP，保留 1 位小数。
    /// 例：530 × 943 = 499,790 px → 0.5 MP
    static func megapixels(width: Int, height: Int) -> Double {
        let px = Double(width) * Double(height)
        return (px / pixelsPerMP).roundedToOneDecimal
    }

    /// 把宽高（像素）换算为 MP，不取整，用于实时显示中间值。
    static func megapixels(width: CGFloat, height: CGFloat) -> Double {
        Double(width * height) / pixelsPerMP
    }

    /// 给定比例和目标 MP，计算具体宽高（像素，已贴近 8 的倍数）。
    ///
    /// 推导：
    ///   w / h = aspect
    ///   w * h = totalPixels
    /// ⇒  w² = totalPixels * aspect
    /// ⇒  h² = totalPixels / aspect
    /// 然后对 w、h 各自向下取整到最近的 8 的倍数。
    static func dimensions(for ratio: CropRatio,
                           megapixels mp: Double) -> (width: Int, height: Int) {
        let totalPixels = mp * pixelsPerMP
        let aspect = Double(ratio.aspectRatio)
        let h = sqrt(totalPixels / aspect)
        let w = aspect * h
        return (roundDownTo8(Int(w.rounded())), roundDownTo8(Int(h.rounded())))
    }

    /// 把数字向下取整到最近的 8 的倍数（最少 8）。
    static func roundDownTo8(_ v: Int) -> Int {
        let result = (v / 8) * 8
        return max(8, result)
    }

    /// 把数字四舍五入到最近的 8 的倍数。
    static func roundTo8(_ v: Int) -> Int {
        let result = ((v + 4) / 8) * 8
        return max(8, result)
    }

    /// 给定比例和某个固定边（通常是受限于原图边界），计算另一边，
    /// 并保证总像素不超过 `maxMegapixels`（防止意外生成超大图）。
    static func fitDimensions(for ratio: CropRatio,
                              constrainedWidth: Int? = nil,
                              constrainedHeight: Int? = nil,
                              maxMegapixels: Double = 100) -> (width: Int, height: Int) {
        let aspect = Double(ratio.aspectRatio)
        var w: Double
        var h: Double
        if let cw = constrainedWidth {
            w = Double(cw)
            h = w / aspect
        } else if let ch = constrainedHeight {
            h = Double(ch)
            w = h * aspect
        } else {
            // 默认按 1 MP 算
            return dimensions(for: ratio, megapixels: 1)
        }
        // 总像素封顶
        let cap = maxMegapixels * pixelsPerMP
        if w * h > cap {
            let scale = sqrt(cap / (w * h))
            w *= scale
            h *= scale
        }
        return (Int(w.rounded()), Int(h.rounded()))
    }

    /// 在指定边界框内，按比例生成「能放下」的最大尺寸（整数像素）。
    /// 用于把剪裁框吸附到原图边界。
    static func largestFitting(for ratio: CropRatio,
                               in bounds: CGSize) -> CGSize {
        let aspect = ratio.aspectRatio
        let boundAspect = bounds.width / bounds.height
        let w: CGFloat
        let h: CGFloat
        if aspect > boundAspect {
            // 受宽度限制
            w = bounds.width
            h = w / aspect
        } else {
            // 受高度限制
            h = bounds.height
            w = h * aspect
        }
        return CGSize(width: floor(w), height: floor(h))
    }
}

extension Double {
    /// 保留 1 位小数（用于显示 MP）。
    var roundedToOneDecimal: Double {
        (self * 10).rounded() / 10
    }

    /// 格式化为 MP 显示字符串，例如 "0.5 MP"。
    var mpDisplay: String {
        let v = roundedToOneDecimal
        // 故意去掉无用的尾零：0.5 → "0.5"，1.0 → "1"
        if v == v.rounded() {
            return "\(Int(v)) MP"
        }
        return String(format: "%.1f MP", v)
    }
}
