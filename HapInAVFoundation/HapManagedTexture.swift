//
//  HapManagedTexture.swift
//  HapInAVFoundation
//
//  Protocols for caller-managed texture lifecycle, used by
//  AVPlayerItemHapMetalOutput. The framework hands back textures
//  wrapped in HapManagedTexture; callers hold them for as long as
//  the underlying MTLTexture is in use, then drop them to return
//  the resource to whichever pool / cache produced it.
//

import Foundation
import Metal

/// A texture handed back by `AVPlayerItemHapMetalOutput.newTexture(forItemTime:)`.
/// Hold the reference for as long as you need the underlying `MTLTexture`;
/// drop it to return the resource to whichever pool / cache produced it.
///
/// Always vended by the caller's `HapTextureAllocator` — the framework
/// itself doesn't allocate or wrap textures. Whatever the allocator
/// returned is what the caller gets back from `newTexture(forItemTime:)`,
/// with the framework having uploaded codec-specific pixel data into
/// `.texture` between the two points.
public protocol HapManagedTexture: AnyObject {
    var texture: MTLTexture { get }
}

/// Allocator the caller supplies to `AVPlayerItemHapMetalOutput` to
/// produce destination textures. Used by both paths:
/// - DXT-direct: framework requests a BC1/BC3/BC7 texture (block-aligned
///   dimensions), uploads compressed DXT bytes via `replace(region:)`.
/// - RGB fallback: framework requests a `.bgra8Unorm` texture at the
///   asset's pixel dimensions, copies decoded RGB bytes via
///   `replace(region:)`.
///
/// The host can wire any buffer-dispensing strategy in here — pool-
/// recycled, fresh allocation, IOSurface-backed, CVMetalTextureCache-
/// backed, whatever. Fresh allocation per frame is correct but slow.
///
/// Requirements on returned textures:
/// - Storage mode `.shared`. The framework uploads via CPU-side
///   `replace(region:)`, which is illegal on `.private`.
/// - Usage at minimum `.shaderRead`. BC formats are sampled-only.
/// - Dimensions exactly as requested.
///
/// Threading: the framework calls `makeTexture` on the same thread
/// that calls `newTexture(forItemTime:)`. Implementations don't need
/// to be thread-safe in themselves.
public protocol HapTextureAllocator: AnyObject {
    func makeTexture(width: Int,
                     height: Int,
                     pixelFormat: MTLPixelFormat) -> (any HapManagedTexture)?
}
