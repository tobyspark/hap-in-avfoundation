#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FilmstripTimelineView;

@protocol FilmstripTimelineViewDelegate <NSObject>
@optional
- (void) filmstripTimelineView:(FilmstripTimelineView *)v didSeekToTime:(CMTime)t;
- (void) filmstripTimelineView:(FilmstripTimelineView *)v didSetInTime:(CMTime)t;
- (void) filmstripTimelineView:(FilmstripTimelineView *)v didSetOutTime:(CMTime)t;
@end

/*
	A horizontal filmstrip timeline:
	- A strip of asynchronously generated thumbnails along the bottom
	- A draggable playhead and draggable in/out handles drawn on top
	- Reports user interaction via its delegate
*/
@interface FilmstripTimelineView : NSView

@property (weak,nullable) id<FilmstripTimelineViewDelegate> delegate;

//	when set, the view will (re)generate thumbnails asynchronously
@property (strong,nonatomic,nullable) AVAsset *asset;

//	natural source duration- supplied by the owner so we can map x positions to times even before thumbnails finish
@property (assign,nonatomic) CMTime duration;

//	in/out time markers (in source-asset time)
@property (assign,nonatomic) CMTime inTime;
@property (assign,nonatomic) CMTime outTime;

//	playhead position (in source-asset time)
@property (assign,nonatomic) CMTime currentTime;

//	informs the view of the desired number of thumbnails (defaults to 24). Set before -setAsset:.
@property (assign,nonatomic) NSInteger thumbnailCount;

@end

NS_ASSUME_NONNULL_END
