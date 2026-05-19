#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>



/**
Class additions to AVAsset that simplify recognizing media containing Hap data

NOTE: the methods below use the deprecated synchronous `tracksWithMediaType:`
accessor internally, which blocks the calling thread until the asset's tracks
have loaded. Use the async equivalents on AVAsset (`loadHapVideoTracks()` /
`loadFirstHapTrack()`) from Swift, which use `loadTracks(withMediaType:)`
(macOS 13+) and don't block. See `AVAssetHapAsync.swift`.
*/
@interface AVAsset (HapInAVFAVAssetAdditions)
/**
Returns a YES if the receiver contains a video track with Hap data.
*/
- (BOOL) containsHapVideoTrack __attribute__((deprecated("Use AVAsset.loadHapVideoTracks() async or loadFirstHapTrack() instead — they use non-deprecated loadTracks(withMediaType:) (macOS 13+).")));
/**
Returns an array populated with instances of AVAssetTrack that contain Hap data.
*/
- (NSArray *) hapVideoTracks __attribute__((deprecated("Use AVAsset.loadHapVideoTracks() async or loadFirstHapTrack() instead — they use non-deprecated loadTracks(withMediaType:) (macOS 13+).")));
@end




/**
Class additions to AVAssetTrack that simplify recognizing tracks containing Hap data
*/
@interface AVAssetTrack (HapInAVFAVAssetTrackAdditions)
/**
Returns a YES if the receiver contains video data compressed using the Hap codec.
*/
- (BOOL) isHapTrack;
@end
