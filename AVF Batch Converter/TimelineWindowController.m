#import "TimelineWindowController.h"
#import "FilmstripTimelineView.h"
#import "FileListController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

//	one window per opened FileHolder; tracked here so we don't dealloc them while open
static NSMutableSet<TimelineWindowController *> *_sLiveWindows = nil;

@interface TimelineWindowController () <FilmstripTimelineViewDelegate, NSWindowDelegate>
@property (strong) FileHolder *file;
@property (weak) FileListController *flc;
@property (strong) AVPlayer *player;
@property (strong) AVPlayerView *playerView;
@property (strong) FilmstripTimelineView *timeline;
@property (strong) NSTextField *currentLabel;
@property (strong) NSTextField *inLabel;
@property (strong) NSTextField *outLabel;
@property (strong) id timeObserver;
@property (strong) id keyMonitor;
@end

@implementation TimelineWindowController

+ (instancetype) showForFile:(FileHolder *)file fileListController:(FileListController *)flc {
	if (file == nil) return nil;
	if (_sLiveWindows == nil) _sLiveWindows = [NSMutableSet set];
	TimelineWindowController *wc = [[TimelineWindowController alloc] initForFile:file fileListController:flc];
	[_sLiveWindows addObject:wc];
	[wc showWindow:nil];
	[wc.window makeKeyAndOrderFront:nil];
	return wc;
}

- (instancetype) initForFile:(FileHolder *)file fileListController:(FileListController *)flc {
	NSRect frame = NSMakeRect(0, 0, 760, 580);
	NSWindow *win = [[NSWindow alloc]
		initWithContentRect:frame
				  styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable)
					backing:NSBackingStoreBuffered
					  defer:NO];
	win.title = [NSString stringWithFormat:@"Timeline — %@", file.srcFileName ?: @""];
	win.releasedWhenClosed = NO;
	[win center];

	self = [super initWithWindow:win];
	if (self == nil) return nil;
	_file = file;
	_flc = flc;
	win.delegate = self;

	[self buildContent];
	[self loadAsset];
	[self installKeyMonitor];

	return self;
}

- (void) installKeyMonitor {
	__weak typeof(self) weakSelf = self;
	self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
		__strong typeof(weakSelf) s = weakSelf;
		if (s == nil) return event;
		//	only act when our window is the key window- otherwise let the event flow normally
		if (event.window != s.window) return event;
		//	plain 'i'/'o' only- don't hijack cmd-i, ctrl-i, etc.
		NSEventModifierFlags mods = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
		mods &= ~(NSEventModifierFlagCapsLock | NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
		if (mods != 0) return event;
		NSString *chars = [event.charactersIgnoringModifiers lowercaseString];
		if ([chars isEqualToString:@"i"]) {
			[s setInPointAtPlayhead];
			return nil;
		}
		if ([chars isEqualToString:@"o"]) {
			[s setOutPointAtPlayhead];
			return nil;
		}
		return event;
	}];
}

- (void) setInPointAtPlayhead {
	CMTime t = self.timeline.currentTime;
	CMTime outT = CMTIME_IS_VALID(self.timeline.outTime) ? self.timeline.outTime : self.timeline.duration;
	if (CMTIME_IS_VALID(outT) && CMTIME_COMPARE_INLINE(t, >=, outT))
		t = CMTimeSubtract(outT, CMTimeMakeWithSeconds(0.05, 600));
	if (CMTIME_COMPARE_INLINE(t, <, kCMTimeZero)) t = kCMTimeZero;
	self.timeline.inTime = t;
	[self refreshLabels];
}

- (void) setOutPointAtPlayhead {
	CMTime t = self.timeline.currentTime;
	CMTime inT = CMTIME_IS_VALID(self.timeline.inTime) ? self.timeline.inTime : kCMTimeZero;
	if (CMTIME_COMPARE_INLINE(t, <=, inT))
		t = CMTimeAdd(inT, CMTimeMakeWithSeconds(0.05, 600));
	if (CMTIME_IS_VALID(self.timeline.duration) && CMTIME_COMPARE_INLINE(t, >, self.timeline.duration))
		t = self.timeline.duration;
	self.timeline.outTime = t;
	[self refreshLabels];
}

- (void) buildContent {
	NSView *root = self.window.contentView;
	NSRect b = root.bounds;

	const CGFloat margin = 12.0;
	const CGFloat buttonRowH = 36.0;
	const CGFloat timelineH = 90.0;
	const CGFloat labelRowH = 22.0;
	CGFloat playerY = margin + buttonRowH + margin + timelineH + margin + labelRowH + margin;

	//	player at the top, fills above the timeline
	AVPlayerView *pv = [[AVPlayerView alloc] initWithFrame:NSMakeRect(margin, playerY, b.size.width - 2*margin, b.size.height - playerY - margin)];
	pv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	pv.controlsStyle = AVPlayerViewControlsStyleInline;
	pv.showsFrameSteppingButtons = YES;
	[root addSubview:pv];
	self.playerView = pv;

	//	time labels row, just above the timeline
	CGFloat labelY = margin + buttonRowH + margin + timelineH + margin;
	CGFloat third = (b.size.width - 2*margin) / 3.0;
	NSTextField *cur = [self makeReadonlyLabelInRect:NSMakeRect(margin, labelY, third, labelRowH)];
	cur.alignment = NSTextAlignmentLeft;
	[root addSubview:cur];
	self.currentLabel = cur;

	NSTextField *inLbl = [self makeReadonlyLabelInRect:NSMakeRect(margin + third, labelY, third, labelRowH)];
	inLbl.alignment = NSTextAlignmentCenter;
	[root addSubview:inLbl];
	self.inLabel = inLbl;

	NSTextField *outLbl = [self makeReadonlyLabelInRect:NSMakeRect(margin + 2*third, labelY, third, labelRowH)];
	outLbl.alignment = NSTextAlignmentRight;
	outLbl.autoresizingMask = NSViewMinXMargin;
	[root addSubview:outLbl];
	self.outLabel = outLbl;

	//	timeline
	FilmstripTimelineView *tl = [[FilmstripTimelineView alloc]
		initWithFrame:NSMakeRect(margin, margin + buttonRowH + margin, b.size.width - 2*margin, timelineH)];
	tl.autoresizingMask = NSViewWidthSizable;
	tl.delegate = self;
	[root addSubview:tl];
	self.timeline = tl;

	//	button row at the bottom
	NSButton *reset = [self makeButtonWithTitle:@"Reset Range" action:@selector(resetRangeClicked:)];
	[reset sizeToFit];
	NSRect rf = reset.frame; rf.origin.x = margin; rf.origin.y = margin; rf.size.height = buttonRowH - 4;
	reset.frame = rf;
	[root addSubview:reset];

	NSButton *update = [self makeButtonWithTitle:@"Update Range" action:@selector(updateRangeClicked:)];
	[update sizeToFit];
	NSRect uf = update.frame; uf.origin.x = NSMaxX(rf) + 8; uf.origin.y = margin; uf.size.height = buttonRowH - 4;
	update.frame = uf;
	[root addSubview:update];

	NSButton *addCut = [self makeButtonWithTitle:@"Add Cut" action:@selector(addCutClicked:)];
	addCut.keyEquivalent = @"\r";
	[addCut sizeToFit];
	NSRect af = addCut.frame; af.size.height = buttonRowH - 4;
	af.origin.x = b.size.width - margin - af.size.width;
	af.origin.y = margin;
	addCut.frame = af;
	addCut.autoresizingMask = NSViewMinXMargin;
	[root addSubview:addCut];

	NSButton *close = [self makeButtonWithTitle:@"Close" action:@selector(closeClicked:)];
	[close sizeToFit];
	NSRect cf = close.frame; cf.size.height = buttonRowH - 4;
	cf.origin.x = af.origin.x - cf.size.width - 8;
	cf.origin.y = margin;
	close.frame = cf;
	close.autoresizingMask = NSViewMinXMargin;
	[root addSubview:close];
}

- (NSTextField *) makeReadonlyLabelInRect:(NSRect)r {
	NSTextField *tf = [[NSTextField alloc] initWithFrame:r];
	tf.bezeled = NO;
	tf.drawsBackground = NO;
	tf.editable = NO;
	tf.selectable = NO;
	tf.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
	tf.stringValue = @"--:--:--.---";
	return tf;
}

- (NSButton *) makeButtonWithTitle:(NSString *)title action:(SEL)sel {
	NSButton *b = [NSButton buttonWithTitle:title target:self action:sel];
	b.bezelStyle = NSBezelStyleRounded;
	return b;
}

#pragma mark - asset / player

- (void) loadAsset {
	NSURL *url = [NSURL fileURLWithPath:[self.file fullSrcPath]];
	AVAsset *asset = [AVAsset assetWithURL:url];
	AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
	AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
	self.player = player;
	self.playerView.player = player;

	CMTime dur = asset.duration;
	self.timeline.duration = dur;
	self.timeline.asset = asset;
	//	pre-populate the timeline with whatever the FileHolder currently has,
	//	falling back to the natural endpoints when invalid
	self.timeline.inTime = CMTIME_IS_VALID(self.file.inTime) ? self.file.inTime : kCMTimeZero;
	self.timeline.outTime = CMTIME_IS_VALID(self.file.outTime) ? self.file.outTime : dur;
	self.timeline.currentTime = self.timeline.inTime;
	[player seekToTime:self.timeline.inTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];

	__weak typeof(self) weakSelf = self;
	self.timeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.05, 600)
															 queue:dispatch_get_main_queue()
														usingBlock:^(CMTime time) {
		__strong typeof(weakSelf) s = weakSelf;
		if (s == nil) return;
		s.timeline.currentTime = time;
		[s refreshLabels];
	}];

	[self refreshLabels];
}

- (void) refreshLabels {
	self.currentLabel.stringValue = [NSString stringWithFormat:@"Now: %@", [self formatTime:self.timeline.currentTime]];
	self.inLabel.stringValue = [NSString stringWithFormat:@"In: %@", [self formatTime:self.timeline.inTime]];
	self.outLabel.stringValue = [NSString stringWithFormat:@"Out: %@", [self formatTime:self.timeline.outTime]];
}

- (NSString *) formatTime:(CMTime)t {
	if (!CMTIME_IS_VALID(t)) return @"--:--:--.---";
	double s = CMTimeGetSeconds(t);
	if (s < 0) s = 0;
	int hh = (int)floor(s / 3600.0);
	int mm = (int)floor(fmod(s, 3600.0) / 60.0);
	int ss = (int)floor(fmod(s, 60.0));
	int ms = (int)round((s - floor(s)) * 1000.0);
	if (ms == 1000) { ms = 0; ss += 1; }
	return [NSString stringWithFormat:@"%02d:%02d:%02d.%03d", hh, mm, ss, ms];
}

#pragma mark - filmstrip delegate

- (void) filmstripTimelineView:(FilmstripTimelineView *)v didSeekToTime:(CMTime)t {
	[self.player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	[self refreshLabels];
}
- (void) filmstripTimelineView:(FilmstripTimelineView *)v didSetInTime:(CMTime)t {
	[self refreshLabels];
}
- (void) filmstripTimelineView:(FilmstripTimelineView *)v didSetOutTime:(CMTime)t {
	[self refreshLabels];
}

#pragma mark - actions

- (void) resetRangeClicked:(id)sender {
	CMTime dur = self.timeline.duration;
	self.timeline.inTime = kCMTimeZero;
	self.timeline.outTime = dur;
	[self refreshLabels];
}

- (void) updateRangeClicked:(id)sender {
	self.file.inTime = self.timeline.inTime;
	self.file.outTime = self.timeline.outTime;
	[self.flc fileHolderRangeChanged:self.file];
}

- (void) addCutClicked:(id)sender {
	CMTimeRange r = CMTimeRangeMake(self.timeline.inTime, CMTimeSubtract(self.timeline.outTime, self.timeline.inTime));
	[self.flc addCutForSourcePath:[self.file fullSrcPath] timeRange:r];
}

- (void) closeClicked:(id)sender {
	[self.window performClose:nil];
}

#pragma mark - lifecycle

- (void) windowWillClose:(NSNotification *)note {
	if (self.timeObserver != nil) {
		[self.player removeTimeObserver:self.timeObserver];
		self.timeObserver = nil;
	}
	if (self.keyMonitor != nil) {
		[NSEvent removeMonitor:self.keyMonitor];
		self.keyMonitor = nil;
	}
	[self.player pause];
	self.playerView.player = nil;
	[_sLiveWindows removeObject:self];
}

@end
