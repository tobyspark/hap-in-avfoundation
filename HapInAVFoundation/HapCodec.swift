//
//  HapCodec.swift
//  HapInAVFoundation
//
//  Swift-friendly enumeration of the Hap codec variants. Raw values
//  are the CoreMedia FourCCs (OSType) carried in a CMFormatDescription's
//  media subtype — the same values defined by the C macros in
//  HapCodecSubTypes.h (kept unchanged for back-compat with existing
//  Obj-C / C consumers that use them as switch-case labels).
//

import Foundation
import Metal
import CoreMedia

/// The Hap codec variants recognised by HapInAVFoundation.
///
/// Raw value is the CoreMedia FourCC `OSType` (e.g. `'Hap1'` packed into
/// 4 bytes). Cross-reference the C macro names below for the canonical
/// definition.
@objc public enum HapCodec: OSType, CaseIterable, Sendable {
    /// Hap — RGB, BC1/DXT1 compressed.
    /// C macro: `kHapCodecSubType`.
    case hap         = 0x48617031   // 'Hap1'
    /// Hap Alpha — RGBA, BC3/DXT5 compressed.
    /// C macro: `kHapAlphaCodecSubType`.
    case hapAlpha    = 0x48617035   // 'Hap5'
    /// Hap 7 — RGBA, BC7 compressed (higher quality than Hap Alpha).
    /// C macro: `kHap7AlphaCodecSubType`.
    case hap7        = 0x48617037   // 'Hap7'
    /// Hap Q — DXT5-encoded scaled YCoCg. Needs colour-space conversion
    /// before display; no direct BC mapping.
    /// C macro: `kHapYCoCgCodecSubType`.
    case hapQ        = 0x48617059   // 'HapY'
    /// Hap Q Alpha — planar (DXT5 YCoCg + RGTC1 alpha). Multi-plane;
    /// no single-texture direct upload path.
    /// C macro: `kHapYCoCgACodecSubType`.
    case hapQAlpha   = 0x4861704D   // 'HapM'
    /// Hap HDR — BC6. The Metal output path in this framework doesn't
    /// yet handle BC6 directly.
    /// C macro: `kHapHDRRGBCodecSubType`.
    case hapHDR      = 0x48617048   // 'HapH'
    /// Hap Alpha-only — single-channel RGTC1 matte.
    /// C macro: `kHapAOnlyCodecSubType`.
    case hapAOnly    = 0x48617041   // 'HapA'

    /// Human-readable name, suitable for logging / UI.
    public var displayName: String {
        switch self {
        case .hap:       return "Hap"
        case .hapAlpha:  return "Hap Alpha"
        case .hap7:      return "Hap 7"
        case .hapQ:      return "Hap Q"
        case .hapQAlpha: return "Hap Q Alpha"
        case .hapHDR:    return "Hap HDR"
        case .hapAOnly:  return "Hap Alpha-only"
        }
    }

    /// FourCC text representation, e.g. `"Hap1"`.
    public var fourCC: String {
        let v = self.rawValue
        return String(unsafeUninitializedCapacity: 4) { buf in
            buf[0] = UInt8((v >> 24) & 0xFF)
            buf[1] = UInt8((v >> 16) & 0xFF)
            buf[2] = UInt8((v >> 8)  & 0xFF)
            buf[3] = UInt8( v        & 0xFF)
            return 4
        }
    }

    /// `true` for codecs whose decoded DXT bytes can be uploaded directly
    /// to a Metal compressed texture: Hap → BC1, Hap Alpha → BC3, Hap 7
    /// → BC7. `false` for variants requiring colour-space conversion,
    /// multi-plane handling, or HDR pixel formats not yet wired up here.
    public var supportsDirectDXTUpload: Bool {
        switch self {
        case .hap, .hapAlpha, .hap7:
            return true
        case .hapQ, .hapQAlpha, .hapHDR, .hapAOnly:
            return false
        }
    }

    /// Metal compressed-texture format the codec's frames map to when
    /// `supportsDirectDXTUpload` is `true`. `nil` for codecs needing
    /// the RGB-via-CVMetalTextureCache fallback.
    public var preferredMTLPixelFormat: MTLPixelFormat? {
        switch self {
        case .hap:        return .bc1_rgba
        case .hapAlpha:   return .bc3_rgba
        case .hap7:       return .bc7_rgbaUnorm
        case .hapQ, .hapQAlpha, .hapHDR, .hapAOnly:
            return nil
        }
    }

    /// Construct from a `CMFormatDescription` media subtype if it's one
    /// of the recognised Hap FourCCs, otherwise `nil`.
    public init?(mediaSubtype: OSType) {
        self.init(rawValue: mediaSubtype)
    }
}
