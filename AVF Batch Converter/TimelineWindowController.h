#import <Cocoa/Cocoa.h>
#import "FileHolder.h"

NS_ASSUME_NONNULL_BEGIN

@class FileListController;

/*
	Window for previewing a source video and defining in/out points to produce
	export items. The "Update Range" button rewrites the source FileHolder's
	in/out; "Add Cut" appends a new FileHolder representing a sub-range of the
	same source.
*/
@interface TimelineWindowController : NSWindowController

+ (instancetype) showForFile:(FileHolder *)file fileListController:(FileListController *)flc;

@end

NS_ASSUME_NONNULL_END
