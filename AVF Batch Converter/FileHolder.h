#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
/*

	this class encapsulates a file- its original path, destination file name, and error string.
	it can also describe a "cut": a sub-range of its source defined by inTime / outTime.

*/

@interface FileHolder : NSObject {
	NSString		*parentDirectoryPath;
	NSString		*srcFileName;
	NSString		*dstFileName;
	NSString		*statusString;
	NSString		*errorString;
	BOOL			conversionDone;
	NSString		*convertedFilePath;
	BOOL			srcFileExists;

	CMTime			inTime;
	CMTime			outTime;
	CMTime			srcDuration;
	NSString		*cutLabel;
}

+ (id) createWithPath:(NSString *)p;
- (id) initWithPath:(NSString *)p;

@property (readonly) NSString *fullSrcPath;
@property (readonly) NSString *parentDirectoryPath;
@property (readonly) NSString *srcFileName;
@property (retain,readwrite) NSString *dstFileName;
@property (retain,readwrite) NSString *statusString;
@property (retain,readwrite) NSString *errorString;
@property (assign,readwrite) BOOL conversionDone;
@property (retain,readwrite) NSString *convertedFilePath;
@property (assign,readwrite) BOOL srcFileExists;

//	in/out points within the source. kCMTimeInvalid means "use the natural endpoint" (start or end of asset).
@property (assign,readwrite) CMTime inTime;
@property (assign,readwrite) CMTime outTime;
//	source duration as discovered at init time. Used to interpret invalid in/out as natural endpoints.
@property (assign,readonly) CMTime srcDuration;
//	non-nil for cuts; inserted before the extension to disambiguate dst names.
@property (retain,readwrite) NSString *cutLabel;

//	YES if inTime/outTime describe a strict subrange of the source.
- (BOOL) isCut;
//	resolved time range (substituting natural endpoints for invalid in/out times).
- (CMTimeRange) resolvedTimeRange;

@end
