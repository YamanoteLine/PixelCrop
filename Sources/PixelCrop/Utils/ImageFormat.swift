//
//  ImageFormat.swift
//  PixelCrop
//
//  支持的图像格式定义与 ImageIO UTType 映射。
//

import Foundation
import UniformTypeIdentifiers
import ImageIO

/// 用户可导入的格式。所有这些 Apple Silicon 上的 ImageIO 原生支持。
enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png
    case heic
    case webp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .heic: return "HEIC"
        case .webp: return "WebP"
        }
    }

    /// 文件扩展名。
    var fileExtension: String { rawValue }

    /// ImageIO 写入时使用的 UTType。
    var utType: CFString {
        switch self {
        case .jpeg: return UTType.jpeg.identifier as CFString
        case .png:  return UTType.png.identifier  as CFString
        case .heic: return UTType.heic.identifier as CFString
        case .webp:
            // macOS 14+ 内置 webp UTType
            if let webP = UTType("org.webmproject.webp") {
                return webP.identifier as CFString
            }
            return "org.webmproject.webp" as CFString
        }
    }

    /// 是否支持质量调节（PNG 是无损，无质量概念）。
    var supportsQuality: Bool { self != .png }

    /// 默认质量。
    var defaultQuality: CGFloat {
        switch self {
        case .jpeg, .webp: return 0.85
        case .heic:        return 0.70
        case .png:         return 1.0
        }
    }

    /// 文件类型对话框里允许打开的类型。
    static var openableTypes: [UTType] {
        var types: [UTType] = [.jpeg, .png, .heic, .image]
        if let webP = UTType.webP { types.append(webP) }
        return types
    }
}

extension UTType {
    /// WebP 在新系统里通过 `org.webmproject.webp` 标识。
    /// macOS 13+ 内置支持，Tahoe 上无任何兼容性问题。
    static var webP: UTType? { UTType("org.webmproject.webp") }
}
