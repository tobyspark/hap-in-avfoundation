//
//  AVAssetHapAsync.swift
//  HapInAVFoundation
//
//  Modern async equivalents of the AVAssetAdditions category methods.
//  Uses `loadTracks(withMediaType:)` (macOS 13+) instead of the
//  deprecated synchronous `tracksWithMediaType:`, and inspects format
//  descriptions via `track.load(.formatDescriptions)` rather than
//  AVAssetTrack's deprecated synchronous accessors.
//

import Foundation
import AVFoundation
import CoreMedia

extension AVAsset {
    /// Async, non-blocking equivalent of `hapVideoTracks`. Loads the
    /// asset's video tracks with the modern `loadTracks(withMediaType:)`
    /// API, then inspects each track's format descriptions for a Hap
    /// codec subtype.
    ///
    /// Returns all Hap video tracks found (typically zero or one).
    public func loadHapVideoTracks() async throws -> [AVAssetTrack] {
        let videoTracks = try await self.loadTracks(withMediaType: .video)
        var results: [AVAssetTrack] = []
        for track in videoTracks {
            let descs = try await track.load(.formatDescriptions)
            if descs.contains(where: { HapCodec(mediaSubtype: CMFormatDescriptionGetMediaSubType($0)) != nil }) {
                results.append(track)
            }
        }
        return results
    }

    /// Convenience: load the first Hap video track and the codec it
    /// carries. Returns `nil` if the asset has no Hap video tracks.
    public func loadFirstHapTrack() async throws -> (track: AVAssetTrack, codec: HapCodec)? {
        let videoTracks = try await self.loadTracks(withMediaType: .video)
        for track in videoTracks {
            let descs = try await track.load(.formatDescriptions)
            for desc in descs {
                if let codec = HapCodec(mediaSubtype: CMFormatDescriptionGetMediaSubType(desc)) {
                    return (track, codec)
                }
            }
        }
        return nil
    }
}
