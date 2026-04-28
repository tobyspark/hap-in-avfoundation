#import <Cocoa/Cocoa.h>
#import "FileHolder.h"
#import "VVKQueue.h"

/*

	this class manages the array of files, and handles their display in the table.
	it's also the class that updates the files' destination paths & error strings
	
	this class is the data source for both table views that list files (the "input" and "output" file table views)

*/

@interface FileListController : NSObject {
	IBOutlet id					fileNameController;
	IBOutlet id					destinationController;
	NSMutableArray				*fileArray;		//	array of 'FileHolder's- this is what will be exported
	
	IBOutlet NSTableView		*srcTableView;
	IBOutlet NSTableView		*dstTableView;
	
	IBOutlet NSTableColumn		*dstNameCol;
	IBOutlet NSTableColumn		*statusCol;
	
	NSTextFieldCell				*statusColTxtFieldCell;
	NSButtonCell				*statusColButtonCell;
	
	VVKQueue					*srcFileQueue;
	VVKQueue					*dstFileQueue;
}

- (IBAction) importButtonUsed:(id)sender;
- (IBAction) clearButtonUsed:(id)sender;

- (void) updateDstFileNames;
//	takes an array of file paths, returns array of file paths (goes through folders in array)
- (NSMutableArray *) flattenFiles:(NSArray *)src toDepth:(int)depth;
//	return the path to the preview movie (either the selected movie or the one bundled with me)
//- (NSString *) pathToPreviewMovie;
//	returns a YES if there are files to export, and the files don't have any errors
- (BOOL) okayToStartExport;

- (void) file:(NSString *)p changed:(u_int)fflag;
- (void) stopWatchingAllPaths;

// Table view data source mehods
- (NSUInteger) numberOfRowsInTableView:(NSTableView *)tv;
- (id) tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)tc row:(int)row;
- (void) tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)tc row:(int)row;
//	data source/drag and drop methods
- (BOOL) tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pb;
- (NSDragOperation) tableView:(NSTableView *)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op;
- (BOOL) tableView:(NSTableView *)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op;
//	delegate methods
//- (void) tableView:(NSTableView *)tv didClickTableColumn:(NSTableColumn *)tc;
- (void) tableView:(NSTableView *)tv deleteRowIndexes:(NSIndexSet *)i;
- (NSCell *) tableView:(NSTableView *)tv dataCellForTableColumn:(NSTableColumn *)tc row:(NSInteger)row;

- (NSMutableArray *) fileArray;

- (FileHolder *) firstFile;
- (FileHolder *) selectedFile;

//	open the timeline window for the double-clicked source row
- (void) srcTableDoubleClicked:(id)sender;

//	called by TimelineWindowController to add a sub-range cut of an existing source file.
//	`userLabel` is the human-typed label (may be nil/empty to auto-number).
- (void) addCutForSourcePath:(NSString *)path timeRange:(CMTimeRange)r;
- (void) addCutForSourcePath:(NSString *)path timeRange:(CMTimeRange)r label:(NSString *)userLabel;

//	called by TimelineWindowController after it edits a FileHolder's in/out
- (void) fileHolderRangeChanged:(FileHolder *)f;

//	rename a cut FileHolder's label (no-op for the unlabeled "original" entry)
- (void) updateLabel:(NSString *)userLabel forFileHolder:(FileHolder *)f;

//	normalize a user-typed label and ensure it doesn't collide with another cut of the
//	same source. pass nil/empty to get the next auto-numbered "_NNN".
- (NSString *) normalizedUniqueLabel:(NSString *)userLabel forSourcePath:(NSString *)path excludingFile:(FileHolder *)excludeFile;

@end
