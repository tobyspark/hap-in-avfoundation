#import "FilmstripTimelineView.h"

typedef NS_ENUM(NSUInteger, FilmstripDragMode) {
	FilmstripDragNone = 0,
	FilmstripDragPlayhead,
	FilmstripDragInHandle,
	FilmstripDragOutHandle,
};

static const CGFloat kHandleWidth = 9.0;
static const CGFloat kHandleHitSlop = 4.0;
static const CGFloat kPlayheadWidth = 1.5;
static const CGFloat kStripInset = 4.0;	//	left/right padding inside the view

@interface FilmstripTimelineView ()
@property (strong) NSMutableArray<NSImage *> *thumbnails;
@property (strong,nullable) AVAssetImageGenerator *imageGenerator;
@property (assign) NSInteger pendingThumbnailGeneration;
@property (assign) FilmstripDragMode dragMode;
@end

@implementation FilmstripTimelineView

- (instancetype) initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_thumbnails = [NSMutableArray arrayWithCapacity:0];
		_thumbnailCount = 24;
		_duration = kCMTimeInvalid;
		_inTime = kCMTimeInvalid;
		_outTime = kCMTimeInvalid;
		_currentTime = kCMTimeZero;
		_dragMode = FilmstripDragNone;
		self.wantsLayer = YES;
	}
	return self;
}

- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstResponder { return YES; }

#pragma mark - geometry

- (NSRect) stripRect {
	NSRect b = self.bounds;
	return NSMakeRect(b.origin.x + kStripInset, b.origin.y + 4.0, b.size.width - (2*kStripInset), b.size.height - 8.0);
}

- (CGFloat) xForTime:(CMTime)t {
	if (!CMTIME_IS_VALID(self.duration) || CMTimeGetSeconds(self.duration) <= 0.0)
		return [self stripRect].origin.x;
	double frac = CMTimeGetSeconds(t) / CMTimeGetSeconds(self.duration);
	if (frac < 0.0) frac = 0.0;
	if (frac > 1.0) frac = 1.0;
	NSRect strip = [self stripRect];
	return strip.origin.x + frac * strip.size.width;
}

- (CMTime) timeForX:(CGFloat)x {
	NSRect strip = [self stripRect];
	if (strip.size.width <= 0.0 || !CMTIME_IS_VALID(self.duration))
		return kCMTimeZero;
	double frac = (x - strip.origin.x) / strip.size.width;
	if (frac < 0.0) frac = 0.0;
	if (frac > 1.0) frac = 1.0;
	double sec = frac * CMTimeGetSeconds(self.duration);
	return CMTimeMakeWithSeconds(sec, self.duration.timescale > 0 ? self.duration.timescale : 60000);
}

- (CMTime) effectiveInTime {
	if (CMTIME_IS_VALID(_inTime)) return _inTime;
	return kCMTimeZero;
}

- (CMTime) effectiveOutTime {
	if (CMTIME_IS_VALID(_outTime)) return _outTime;
	return CMTIME_IS_VALID(self.duration) ? self.duration : kCMTimeZero;
}

#pragma mark - thumbnails

- (void) setAsset:(AVAsset *)asset {
	_asset = asset;
	[self.thumbnails removeAllObjects];
	if (asset == nil) {
		self.imageGenerator = nil;
		[self setNeedsDisplay:YES];
		return;
	}
	if (!CMTIME_IS_VALID(self.duration) || CMTimeGetSeconds(self.duration) <= 0.0)
		self.duration = asset.duration;

	AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
	gen.appliesPreferredTrackTransform = YES;
	gen.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.5, 600);
	gen.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.5, 600);
	//	keep thumbnails small to avoid heavy memory use
	gen.maximumSize = CGSizeMake(160.0, 90.0);
	self.imageGenerator = gen;

	NSInteger n = self.thumbnailCount;
	if (n < 1) n = 1;
	NSMutableArray<NSValue *> *times = [NSMutableArray arrayWithCapacity:n];
	double dur = CMTimeGetSeconds(self.duration);
	for (NSInteger i = 0; i < n; ++i) {
		double frac = (n == 1) ? 0.5 : ((double)i + 0.5) / (double)n;
		CMTime t = CMTimeMakeWithSeconds(frac * dur, 600);
		[times addObject:[NSValue valueWithCMTime:t]];
		//	placeholder; replaced as thumbnails arrive (drawRect ignores non-NSImage entries)
		[self.thumbnails addObject:(NSImage *)[NSNull null]];
	}

	NSInteger gen_id = ++self.pendingThumbnailGeneration;
	__weak typeof(self) weakSelf = self;
	[gen generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef _Nullable image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
		if (image == NULL || result != AVAssetImageGeneratorSucceeded) return;
		//	figure out which slot this corresponds to
		__strong typeof(weakSelf) strong = weakSelf;
		if (strong == nil) return;
		if (strong.pendingThumbnailGeneration != gen_id) return;
		double frac = CMTimeGetSeconds(requestedTime) / dur;
		NSInteger idx = (NSInteger)floor(frac * n);
		if (idx < 0) idx = 0;
		if (idx >= n) idx = n - 1;
		NSImage *img = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image))];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (strong.pendingThumbnailGeneration != gen_id) return;
			if (idx < (NSInteger)strong.thumbnails.count)
				strong.thumbnails[idx] = img;
			[strong setNeedsDisplay:YES];
		});
	}];
	[self setNeedsDisplay:YES];
}

#pragma mark - drawing

- (void) drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	NSRect strip = [self stripRect];

	//	background
	[[NSColor colorWithWhite:0.10 alpha:1.0] setFill];
	NSRectFill(strip);

	//	thumbnails (each evenly spaced across the strip)
	NSInteger n = self.thumbnails.count;
	if (n > 0) {
		CGFloat slot = strip.size.width / (CGFloat)n;
		for (NSInteger i = 0; i < n; ++i) {
			id obj = self.thumbnails[i];
			if (![obj isKindOfClass:[NSImage class]]) continue;
			NSImage *img = (NSImage *)obj;
			NSRect dst = NSMakeRect(strip.origin.x + i*slot, strip.origin.y, slot, strip.size.height);
			NSRect inset = NSInsetRect(dst, 0.5, 0.5);
			[img drawInRect:inset
				   fromRect:NSZeroRect
				  operation:NSCompositingOperationCopy
				   fraction:1.0
			 respectFlipped:YES
					  hints:nil];
		}
	}

	//	dim the area outside the in/out range
	CGFloat inX = [self xForTime:[self effectiveInTime]];
	CGFloat outX = [self xForTime:[self effectiveOutTime]];
	[[NSColor colorWithWhite:0.0 alpha:0.5] setFill];
	if (inX > strip.origin.x) {
		NSRectFillUsingOperation(NSMakeRect(strip.origin.x, strip.origin.y, inX - strip.origin.x, strip.size.height), NSCompositingOperationSourceOver);
	}
	if (outX < NSMaxX(strip)) {
		NSRectFillUsingOperation(NSMakeRect(outX, strip.origin.y, NSMaxX(strip) - outX, strip.size.height), NSCompositingOperationSourceOver);
	}

	//	in handle (cyan triangle, left edge)
	[[NSColor colorWithRed:0.20 green:0.85 blue:0.95 alpha:1.0] setFill];
	NSBezierPath *inPath = [NSBezierPath bezierPath];
	[inPath moveToPoint:NSMakePoint(inX, strip.origin.y)];
	[inPath lineToPoint:NSMakePoint(inX, NSMaxY(strip))];
	[inPath lineToPoint:NSMakePoint(inX + kHandleWidth, NSMaxY(strip))];
	[inPath lineToPoint:NSMakePoint(inX + kHandleWidth, strip.origin.y + 4.0)];
	[inPath lineToPoint:NSMakePoint(inX + 2.0, strip.origin.y)];
	[inPath closePath];
	[inPath fill];

	//	out handle
	[[NSColor colorWithRed:1.0 green:0.55 blue:0.20 alpha:1.0] setFill];
	NSBezierPath *outPath = [NSBezierPath bezierPath];
	[outPath moveToPoint:NSMakePoint(outX, strip.origin.y)];
	[outPath lineToPoint:NSMakePoint(outX, NSMaxY(strip))];
	[outPath lineToPoint:NSMakePoint(outX - kHandleWidth, NSMaxY(strip))];
	[outPath lineToPoint:NSMakePoint(outX - kHandleWidth, strip.origin.y + 4.0)];
	[outPath lineToPoint:NSMakePoint(outX - 2.0, strip.origin.y)];
	[outPath closePath];
	[outPath fill];

	//	playhead
	CGFloat phX = [self xForTime:self.currentTime];
	[[NSColor whiteColor] setFill];
	NSRect phRect = NSMakeRect(phX - kPlayheadWidth/2.0, strip.origin.y - 2.0, kPlayheadWidth, strip.size.height + 4.0);
	NSRectFill(phRect);
	//	little knob on top
	NSBezierPath *knob = [NSBezierPath bezierPath];
	[knob moveToPoint:NSMakePoint(phX - 4.0, NSMaxY(strip) + 2.0)];
	[knob lineToPoint:NSMakePoint(phX + 4.0, NSMaxY(strip) + 2.0)];
	[knob lineToPoint:NSMakePoint(phX, NSMaxY(strip) - 4.0)];
	[knob closePath];
	[knob fill];

	//	border
	[[NSColor colorWithWhite:0.4 alpha:1.0] setStroke];
	NSFrameRect(strip);
}

#pragma mark - mouse handling

- (FilmstripDragMode) dragModeForPoint:(NSPoint)p modifiers:(NSEventModifierFlags)m {
	NSRect strip = [self stripRect];
	if (!NSPointInRect(p, NSInsetRect(strip, 0, -8))) return FilmstripDragNone;

	//	exact handle hits win regardless of modifiers, so the visible handles always grab
	CGFloat inX = [self xForTime:[self effectiveInTime]];
	CGFloat outX = [self xForTime:[self effectiveOutTime]];
	if (fabs(p.x - inX) <= (kHandleWidth + kHandleHitSlop)) return FilmstripDragInHandle;
	if (fabs(p.x - outX) <= (kHandleWidth + kHandleHitSlop)) return FilmstripDragOutHandle;

	//	a body click with option redirects the drag to the in handle, with command to the out handle
	if (m & NSEventModifierFlagOption) return FilmstripDragInHandle;
	if (m & NSEventModifierFlagCommand) return FilmstripDragOutHandle;
	return FilmstripDragPlayhead;
}

- (void) mouseDown:(NSEvent *)event {
	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	self.dragMode = [self dragModeForPoint:p modifiers:event.modifierFlags];
	if (self.dragMode == FilmstripDragNone) return;
	[self handleDragToPoint:p];
}

- (void) mouseDragged:(NSEvent *)event {
	if (self.dragMode == FilmstripDragNone) return;
	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	[self handleDragToPoint:p];
}

- (void) mouseUp:(NSEvent *)event {
	self.dragMode = FilmstripDragNone;
}

- (void) handleDragToPoint:(NSPoint)p {
	CMTime t = [self timeForX:p.x];
	switch (self.dragMode) {
		case FilmstripDragPlayhead: {
			self.currentTime = t;
			[self setNeedsDisplay:YES];
			if ([self.delegate respondsToSelector:@selector(filmstripTimelineView:didSeekToTime:)])
				[self.delegate filmstripTimelineView:self didSeekToTime:t];
			break;
		}
		case FilmstripDragInHandle: {
			//	clamp so in <= out - 1 frame's worth of slack
			CMTime out = [self effectiveOutTime];
			if (CMTIME_COMPARE_INLINE(t, >=, out)) {
				t = CMTimeSubtract(out, CMTimeMakeWithSeconds(0.05, 600));
			}
			if (CMTIME_COMPARE_INLINE(t, <, kCMTimeZero)) t = kCMTimeZero;
			self.inTime = t;
			[self setNeedsDisplay:YES];
			if ([self.delegate respondsToSelector:@selector(filmstripTimelineView:didSetInTime:)])
				[self.delegate filmstripTimelineView:self didSetInTime:t];
			break;
		}
		case FilmstripDragOutHandle: {
			CMTime inT = [self effectiveInTime];
			if (CMTIME_COMPARE_INLINE(t, <=, inT)) {
				t = CMTimeAdd(inT, CMTimeMakeWithSeconds(0.05, 600));
			}
			if (CMTIME_IS_VALID(self.duration) && CMTIME_COMPARE_INLINE(t, >, self.duration))
				t = self.duration;
			self.outTime = t;
			[self setNeedsDisplay:YES];
			if ([self.delegate respondsToSelector:@selector(filmstripTimelineView:didSetOutTime:)])
				[self.delegate filmstripTimelineView:self didSetOutTime:t];
			break;
		}
		default: break;
	}
}

#pragma mark - setters that redraw

- (void) setCurrentTime:(CMTime)t {
	_currentTime = t;
	[self setNeedsDisplay:YES];
}
- (void) setInTime:(CMTime)t {
	_inTime = t;
	[self setNeedsDisplay:YES];
}
- (void) setOutTime:(CMTime)t {
	_outTime = t;
	[self setNeedsDisplay:YES];
}
- (void) setDuration:(CMTime)d {
	_duration = d;
	[self setNeedsDisplay:YES];
}

@end
