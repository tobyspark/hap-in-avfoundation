//
//  AVPlayerItemHapMetalOutput.swift
//  HapInAVFoundation
//
//  High-level convenience over AVPlayerItemHapDXTOutput: yields
//  ready-to-sample MTLTextures from a Hap-encoded AVPlayerItem,
//  picking the fastest path the asset's codec allows.
//

import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import Metal
import os

/// Yields `MTLTexture`s from a Hap-encoded `AVPlayerItem`, picking the
/// fastest path the asset's codec allows.
///
/// Two paths internally:
/// - **DXT-direct** (Hap, Hap Alpha, Hap 7): the decoder's compressed
///   DXT bytes are uploaded straight to a BC1/BC3/BC7 `MTLTexture` via
///   `replace(region:)`.
/// - **RGB fallback** (Hap Q, Hap Q Alpha, Hap HDR, Hap Alpha-only):
///   the decoder emits BGRA8 pixel data; the framework copies it into
///   a `.bgra8Unorm` `MTLTexture` via `replace(region:)`.
///
/// Both paths source their destination textures from the caller-
/// supplied `HapTextureAllocator`. The allocator owns the recycling
/// / pooling / IOSurface strategy.
///
/// The mode is fixed at construction based on the asset's codec.
/// `mode == .noHapTrack` means the asset has no Hap video tracks —
/// the caller should fall back to a standard `AVPlayerItemVideoOutput`.
///
/// **Per-tick usage.** Call `newTexture(forItemTime:)` once per render
/// tick. It returns nil when there's no new frame to emit (decoder
/// isn't ready yet, or the closest frame to `itemTime` has the same
/// presentation time as the previous emit). When non-nil, send the
/// returned texture downstream.
///
/// This matches `AVPlayerItemVideoOutput.copyPixelBuffer`'s "returns
/// nil if nothing new" semantic. There's no separate `hasNewFrame`
/// peek because the underlying `AVPlayerItemHapDXTOutput`'s decoder
/// queue is driven by `allocFrameClosest(to:)` — a peek-only API
/// would never see frames decoded.
///
/// **Threading.** The class holds mutable state (`lastEmittedTime`,
/// the once-per-instance log flag) that is read and written without
/// synchronisation. Callers must serialise `newTexture(forItemTime:)`
/// calls — typically by calling from a single per-tick render loop.
/// `init` and `remove(from:)` are likewise single-threaded with
/// respect to the other methods.
///
/// **Lifecycle.** The init attaches an internal `AVPlayerItemHapDXTOutput`
/// to `playerItem`. Call `remove(from:)` before the player item is
/// replaced. Returned `HapManagedTexture`s are ARC-tracked; drop them
/// to return resources to whichever pool the allocator manages.
public final class AVPlayerItemHapMetalOutput {

    /// Path selected at construction based on the asset's first Hap
    /// video track's codec subtype.
    public enum Mode: Sendable, Equatable {
        /// Decoder emits DXT bytes; framework uploads to a
        /// caller-allocated BC-format texture each frame.
        case dxtDirect(HapCodec)
        /// Decoder emits BGRA8; framework copies into a
        /// caller-allocated `.bgra8Unorm` texture each frame.
        case rgbFallback(HapCodec)
        /// The asset has no Hap video track. `newTexture` always
        /// returns `nil`; `itemTime(forHostTime:)` returns `.invalid`.
        /// Caller should fall back to a standard `AVPlayerItemVideoOutput`.
        case noHapTrack
    }

    /// Errors thrown from the async init when something goes wrong
    /// past the "has Hap track" gate. (No-Hap-track is not an error —
    /// it's represented as `Mode.noHapTrack`.)
    public enum InitializationError: Swift.Error {
        /// `AVPlayerItemHapDXTOutput(hapAssetTrack:)` returned nil for
        /// a track that was identified as Hap. Indicates either a
        /// framework bug or a malformed Hap track.
        case hapOutputConstructionFailed
    }

    public let mode: Mode

    private static let log = Logger(subsystem: "io.vidvox.hapinavfoundation",
                                    category: "AVPlayerItemHapMetalOutput")

    private let textureAllocator: any HapTextureAllocator

    /// Set when a Hap track was found and attached at init; left nil
    /// when `mode == .noHapTrack`. The two states are equivalent —
    /// the field exists separately so `remove(from:)`, `itemTime`,
    /// and `newTexture` can guard on it directly without pattern-
    /// matching on `mode`.
    private let hapDXTOutput: AVPlayerItemHapDXTOutput?

    /// Presentation time of the most recently emitted frame. Drives
    /// the dedupe gate in `newTexture(forItemTime:)`. `.invalid`
    /// initially so the first post-init call is never deduped. See
    /// the class doc — this field is expected to be touched only
    /// from the caller's render loop.
    private var lastEmittedTime: CMTime = .invalid

    /// One-shot flag so the BC sub-block-alignment notice in
    /// `makeDXTTexture` fires at most once per output instance.
    private var didLogSubBlockPadding: Bool = false

    /// Create and attach to `playerItem`. Detects the asset's first
    /// Hap video track asynchronously via the modern
    /// `loadTracks(withMediaType:)` API; the init returns once the
    /// underlying output is wired up.
    ///
    /// - Parameters:
    ///   - playerItem: the player item to attach the internal Hap
    ///     output to.
    ///   - textureAllocator: produces destination `MTLTexture`s for
    ///     both DXT and RGB paths. See `HapTextureAllocator`.
    public init(playerItem: AVPlayerItem,
                textureAllocator: any HapTextureAllocator) async throws {
        self.textureAllocator = textureAllocator

        guard let found = try await playerItem.asset.loadFirstHapTrack() else {
            self.mode = .noHapTrack
            self.hapDXTOutput = nil
            return
        }

        guard let output = AVPlayerItemHapDXTOutput(hapAssetTrack: found.track) else {
            throw InitializationError.hapOutputConstructionFailed
        }
        let useDirectDXT = found.codec.supportsDirectDXTUpload
        output.outputAsRGB = !useDirectDXT
        if !useDirectDXT {
            output.destRGBPixelFormat = OSType(kCVPixelFormatType_32BGRA)
        }
        output.suppressesPlayerRendering = true
        playerItem.add(output)

        self.hapDXTOutput = output
        self.mode = useDirectDXT
            ? .dxtDirect(found.codec)
            : .rgbFallback(found.codec)
    }

    /// Detach the internal output from `playerItem`. No-op when
    /// `mode == .noHapTrack` (nothing was attached in that case), so
    /// callers don't need to branch on `mode` at teardown time.
    public func remove(from playerItem: AVPlayerItem) {
        if let output = hapDXTOutput {
            playerItem.remove(output)
        }
    }

    /// Forward to the internal output. Returns `.invalid` when
    /// `mode == .noHapTrack`.
    public func itemTime(forHostTime hostTime: CFTimeInterval) -> CMTime {
        guard let output = hapDXTOutput else { return .invalid }
        return output.itemTime(forHostTime: hostTime)
    }

    /// Decode the frame closest to `itemTime`, upload to a fresh
    /// managed texture, return it. Returns `nil` when:
    /// - `mode == .noHapTrack` — there is no Hap output to decode from,
    /// - the underlying decoder has no frame ready yet (typically the
    ///   first few ticks after attach — `AVPlayerItemHapDXTOutput`'s
    ///   `allocFrameClosest(to:)` is asynchronous),
    /// - the closest frame's presentation time matches the previously
    ///   emitted frame's (dedupe — nothing new to send), or
    /// - the texture allocator returned `nil`.
    ///
    /// Calling this method drives the decoder's queue forward — call
    /// it once per render tick whether or not you previously got a
    /// frame back. Skipping ticks delays the decode pipeline.
    public func newTexture(forItemTime itemTime: CMTime) -> (any HapManagedTexture)? {
        guard let output = hapDXTOutput,
              let frame = output.allocFrameClosest(to: itemTime)
        else { return nil }

        // Dedupe: skip if this is the same frame we already emitted.
        // `CMTimeCompare`'s behaviour is undefined on `.invalid`, hence
        // the explicit `isValid` check for the first-call case.
        if lastEmittedTime.isValid,
           CMTimeCompare(frame.presentationTime, lastEmittedTime) == 0
        {
            return nil
        }

        let managed: (any HapManagedTexture)?
        switch mode {
        case .dxtDirect(let codec):
            managed = makeDXTTexture(from: frame, codec: codec)
        case .rgbFallback:
            managed = makeRGBTexture(from: frame)
        case .noHapTrack:
            managed = nil
        }
        if managed != nil {
            lastEmittedTime = frame.presentationTime
        }
        return managed
    }

    // MARK: - DXT direct upload

    private func makeDXTTexture(from frame: HapDecoderFrame,
                                codec: HapCodec) -> (any HapManagedTexture)? {
        // Hap Q Alpha is two-plane; this single-plane upload path
        // doesn't handle that. (In practice we wouldn't reach here —
        // Hap Q Alpha's codec doesn't claim supportsDirectDXTUpload,
        // so `mode` would be .rgbFallback — but guard defensively.)
        guard frame.dxtPlaneCount == 1 else { return nil }
        guard let pixelFormat = codec.preferredMTLPixelFormat else { return nil }

        let dxtW = Int(frame.dxtImgSize.width)
        let dxtH = Int(frame.dxtImgSize.height)
        let trueW = Int(frame.imgSize.width)
        let trueH = Int(frame.imgSize.height)
        guard dxtW > 0, dxtH > 0, trueW > 0, trueH > 0 else { return nil }

        // BC1 / BC3 / BC7 require texture dimensions that are multiples
        // of 4 (one compressed block per 4×4 pixel region). When the
        // asset's true size doesn't satisfy that, fall back to the
        // padded `dxtImgSize` and log once per output instance —
        // re-encoding at a multiple-of-4 resolution is the user-visible
        // fix.
        let blockAligned = (trueW % 4 == 0) && (trueH % 4 == 0)
        let texW: Int
        let texH: Int
        if blockAligned {
            texW = trueW
            texH = trueH
        } else {
            if !didLogSubBlockPadding {
                Self.log.notice("Hap DXT asset is \(trueW)×\(trueH) — not a multiple of 4. BC textures require block-aligned dimensions; falling back to padded \(dxtW)×\(dxtH). Re-encode at a multiple-of-4 resolution to drop the right/bottom padding pixels.")
                didLogSubBlockPadding = true
            }
            texW = dxtW
            texH = dxtH
        }

        let dxtData = frame.dxtDatas[0]
        guard dxtData != nil else { return nil }

        guard let managed = textureAllocator.makeTexture(width: texW,
                                                         height: texH,
                                                         pixelFormat: pixelFormat)
        else {
            Self.log.error("DXT texture allocator returned nil for \(texW)×\(texH) \(String(describing: pixelFormat))")
            return nil
        }

        // BC1 packs a 4×4 block into 8 bytes; BC3 / BC7 into 16.
        // Row stride is always derived from the padded `dxtW` — that's
        // the stride the decoder actually wrote — even when the
        // destination texture is the smaller true-size.
        let blocksPerRow = (dxtW + 3) / 4
        let bytesPerBlock = (pixelFormat == .bc1_rgba) ? 8 : 16
        let bytesPerRow = blocksPerRow * bytesPerBlock

        let region = MTLRegionMake2D(0, 0, texW, texH)
        managed.texture.replace(region: region, mipmapLevel: 0,
                                withBytes: dxtData!, bytesPerRow: bytesPerRow)
        return managed
    }

    // MARK: - RGB fallback

    private func makeRGBTexture(from frame: HapDecoderFrame) -> (any HapManagedTexture)? {
        guard let rgbData = frame.rgbData else { return nil }
        let width = Int(frame.rgbImgSize.width)
        let height = Int(frame.rgbImgSize.height)
        guard width > 0, height > 0, frame.rgbDataSize > 0 else { return nil }

        // Decoder writes tightly-packed BGRA8 (we set `destRGBPixelFormat`
        // to kCVPixelFormatType_32BGRA at init). `rgbDataSize / height`
        // gives us the actual row stride the decoder used — generally
        // `width * 4` but compute defensively.
        let srcStride = frame.rgbDataSize / height

        guard let managed = textureAllocator.makeTexture(width: width,
                                                         height: height,
                                                         pixelFormat: .bgra8Unorm)
        else {
            Self.log.error("RGB texture allocator returned nil for \(width)×\(height) BGRA8")
            return nil
        }

        let region = MTLRegionMake2D(0, 0, width, height)
        managed.texture.replace(region: region, mipmapLevel: 0,
                                withBytes: rgbData, bytesPerRow: srcStride)
        return managed
    }
}
