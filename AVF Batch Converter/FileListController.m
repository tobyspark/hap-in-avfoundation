#import "FileListController.h"
#import "FileNameController.h"
#import "DestinationController.h"
#import "TimelineWindowController.h"




@implementation FileListController


- (id) init	{
	self = [super init];
	fileArray = [NSMutableArray arrayWithCapacity:0];
	statusColTxtFieldCell = [[NSTextFieldCell alloc] initTextCell:@"asdf"];
	[statusColTxtFieldCell setControlSize:NSControlSizeMini];
	
	statusColButtonCell = [[NSButtonCell alloc] init];
	[statusColButtonCell setControlSize:NSControlSizeSmall];
	[statusColButtonCell setFont:[NSFont fontWithName:@"Lucida Grande" size:10]];
	[statusColButtonCell setButtonType:NSButtonTypeMomentaryPushIn];
	[statusColButtonCell setTitle:@"Show in Finder"];
	[statusColButtonCell setBezelStyle:NSBezelStyleAccessoryBarAction];
	
	srcFileQueue = [[VVKQueue alloc] init];
	[srcFileQueue setDelegate:self];
	dstFileQueue = [[VVKQueue alloc] init];
	[dstFileQueue setDelegate:self];
	
	return self;
}
/*------------------------------------*/
- (void) awakeFromNib	{
	//	register to receive drops from the finder
	[srcTableView registerForDraggedTypes:[NSArray arrayWithObjects:@"FileHolderIndexSet",NSPasteboardTypeFileURL,nil]];
	//	double-click a row to open its filmstrip / in-out editor
	[srcTableView setTarget:self];
	[srcTableView setDoubleAction:@selector(srcTableDoubleClicked:)];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (IBAction) importButtonUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSOpenPanel			*openPanel = [NSOpenPanel openPanel];
	
	
	//	set up the open panel
	[openPanel setAllowsMultipleSelection:YES];
	//[openPanel setDelegate:self];
	[openPanel setTitle:@"Choose some AVFoundation-compatible movies to transcode:"];
	[openPanel setPrompt:@"Select"];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowedFileTypes:[NSArray arrayWithObjects:@"mov",@"fold",@"mp4",@"mpg",@"avi",nil]];
	
	//	following executes when the panel returns
	if ([openPanel runModal] == NSModalResponseOK)	{
		NSArray				*importedFileURLs = [openPanel URLs];
		NSMutableArray		*importedFiles = [NSMutableArray arrayWithCapacity:0];
		for (NSURL *urlPtr in importedFileURLs)
			[importedFiles addObject:[urlPtr path]];
		NSMutableArray		*flattenedFileArray = [self flattenFiles:importedFiles toDepth:1];
		NSEnumerator		*it;
		NSString			*path;
		FileHolder			*newObj;
		
		//	if the flattened file array is nil (or empty), just return right now
		if ((flattenedFileArray == nil) || ([flattenedFileArray count] < 1))
			return;
		//	run through the flattened file array, adding the contents to the file array
		it = [flattenedFileArray objectEnumerator];
		while (path = [it nextObject])	{
			BOOL		fresh = ![self fileArrayContainsSourcePath:path];
			newObj = [FileHolder createWithPath:path];
			if (newObj != nil)	{
				[fileArray addObject:newObj];
				if (fresh)
					[self loadCutsFromSidecarForFile:newObj];
			}
		}
		//	run through all the files, updating the dst. file names & error strings
		[self updateDstFileNames];
		//	update the table view
		[srcTableView deselectAll:nil];
		[srcTableView reloadData];
		[dstTableView deselectAll:nil];
		[dstTableView reloadData];
	}
}
/*------------------------------------*/
- (IBAction) clearButtonUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	//[srcFileQueue stopWatchingAllPaths];
	[fileArray removeAllObjects];
	[srcTableView reloadData];
	[dstTableView reloadData];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (void) updateDstFileNames	{
	NSEnumerator		*it = [fileArray objectEnumerator];
	FileHolder			*filePtr;
	NSString			*fullDstPath;
	NSFileManager		*fileManager = [NSFileManager defaultManager];
	
	[self stopWatchingAllPaths];
	
	while (filePtr = [it nextObject])	{
		//	make sure the original source file actually exists
		[filePtr setSrcFileExists:[fileManager fileExistsAtPath:[filePtr fullSrcPath]]];
		//	watch the source file's parent folder (if the src exists)
		if ([filePtr srcFileExists])	{
			[srcFileQueue watchPath:[filePtr parentDirectoryPath]];
		}
		//	use the file name controller to set the file's destination name; for cuts, suffix
		//	the basename with the cutLabel before the extension so each cut writes a unique file
		NSString		*dstBase = [fileNameController getDstNameForOrigName:[filePtr srcFileName]];
		if ([[filePtr cutLabel] length] > 0)	{
			NSString	*ext = [dstBase pathExtension];
			NSString	*root = [dstBase stringByDeletingPathExtension];
			if ([ext length] > 0)
				dstBase = [NSString stringWithFormat:@"%@%@.%@", root, [filePtr cutLabel], ext];
			else
				dstBase = [NSString stringWithFormat:@"%@%@", root, [filePtr cutLabel]];
		}
		[filePtr setDstFileName:dstBase];
		//	check for errors (file already exists)
		if ([destinationController sameAsOriginal])	{
			fullDstPath = [NSString stringWithFormat:@"%@%@",[filePtr parentDirectoryPath],[filePtr dstFileName]];
			[dstFileQueue watchPath:[filePtr parentDirectoryPath]];
		}
		else	{
			fullDstPath = [NSString stringWithFormat:@"%@%@",[destinationController destinationPathString],[filePtr dstFileName]];
			[dstFileQueue watchPath:[destinationController destinationPathString]];
		}
		
		if (![filePtr srcFileExists])	{
			[filePtr setStatusString:@"Src Missing"];
		}
		else if ([fileManager fileExistsAtPath:fullDstPath])	{
			[filePtr setStatusString:@"Already Exists"];
		}
		else	{
			[filePtr setStatusString:@"Ready"];
			[filePtr setConversionDone:NO];
			[filePtr setConvertedFilePath:nil];
		}
	}
}
/*------------------------------------*/
- (NSMutableArray *) flattenFiles:(NSArray *)src toDepth:(int)depth	{
	if ((src == nil) || ([src count] <= 0))
		return nil;
	if (depth < 0)
		return nil;
	NSFileManager			*fm = [NSFileManager defaultManager];
	NSMutableArray			*returnMe = [NSMutableArray arrayWithCapacity:0];
	NSEnumerator			*srcIt = [src objectEnumerator];
	NSString				*path = nil;
	BOOL					folderFlag = NO;
	
	//	run through the paths
	while (path = [srcIt nextObject])	{
		//	make sure there's a valid file at the path & determine if it's a folder or not
		if ([fm fileExistsAtPath:path isDirectory:&folderFlag])	{
			//	if it's a folder, call this method recursively & add the results to my return array
			if ((folderFlag) && (depth > 0))	{
				NSArray				*partialSubpathsArray = [fm contentsOfDirectoryAtPath:path error:nil];
				NSEnumerator		*subpathIt = [partialSubpathsArray objectEnumerator];
				NSString			*subpath;
				NSMutableArray		*fullSubpathsArray = [NSMutableArray arrayWithCapacity:0];
				
				while (subpath = [subpathIt nextObject])
					[fullSubpathsArray addObject:[NSString stringWithFormat:@"%@/%@",path,subpath]];
				[returnMe addObjectsFromArray:[self flattenFiles:fullSubpathsArray toDepth:(depth-1)]];
			}
			//	else if it's a file, add its path to my return array
			else
				[returnMe addObject:path];
		}
	}
	
	return returnMe;
}
/*------------------------------------*/
/*
- (NSString *) pathToPreviewMovie	{
	int			selectedRow = [srcTableView selectedRow];
	
	//	if i've selected something in the table view, return the path to the (1st) selected item
	if (selectedRow != (-1))	{
		FileHolder		*filePtr = [fileArray objectAtIndex:selectedRow];
		return [NSString stringWithFormat:@"%@%@",[filePtr parentDirectoryPath],[filePtr srcFileName]];
	}
	//	if nothing's selected, return the path to the movie bundled with me
	else	{
		return [[NSBundle mainBundle] pathForResource:@"SampleMovie" ofType:@"mov"];
	}
}
 */
/*------------------------------------*/
- (BOOL) okayToStartExport	{
	if (fileArray == nil)
		return NO;
	if ([fileArray count] < 1)
		return NO;
	
	NSEnumerator		*fileIt = [fileArray objectEnumerator];
	FileHolder			*filePtr;
	while (filePtr = [fileIt nextObject])	{
		if (![[filePtr statusString] isEqualToString:@"Ready"])	{
			NSLog(@"\t\terr: status of file %@ preventing export in %s",filePtr,__func__);
			return NO;
		}
		else if ([filePtr errorString]!=nil)	{
			NSLog(@"\t\terr: error of file %@ preventing export in %s",filePtr,__func__);
			return NO;
		}
	}
	return YES;
}
/*------------------------------------*/
- (void) file:(NSString *)p changed:(u_int)fflag	{
	//NSLog(@"\t\t%ld, %@",fflag,p);
	[self updateDstFileNames];
	[srcTableView reloadData];
	[dstTableView reloadData];
	//NSLog(@"\t\tFileListController:file:changed: - FINISHED");
}
/*------------------------------------*/
- (void) stopWatchingAllPaths	{
	[srcFileQueue stopWatchingAllPaths];
	[dstFileQueue stopWatchingAllPaths];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
// Table view data source mehods
- (NSUInteger) numberOfRowsInTableView:(NSTableView *)tv	{
	return [fileArray count];
}
/*------------------------------------*/
- (id) tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)tc row:(int)row	{
	FileHolder		*filePtr = [fileArray objectAtIndex:row];
	
	if (filePtr == nil)
		return nil;
	
	if (tv == srcTableView)	{
		return [filePtr srcFileName];
	}
	else if (tv == dstTableView)	{
		if (tc == dstNameCol)	{
			return [filePtr dstFileName];
		}
		else if (tc == statusCol)	{
			NSString		*errorString = [filePtr errorString];
			if (errorString!=nil)	{
				//return errorString;
				return @"Error!";
			}
			else
				return [filePtr statusString];
		}
	}
	/*
	if (tc == sourceNameCol)	{
		return [filePtr srcFileName];
	}
	else if (tc == destNameCol)	{
		return [filePtr dstFileName];
	}
	else if (tc == statusCol)	{
		return [filePtr errorString];
	}
	*/
	return nil;
}
/*------------------------------------*/
- (void) tableView:(NSTableView *)tv setObjectValue:(id)v forTableColumn:(NSTableColumn *)tc row:(int)row	{
	if (tv == srcTableView)
		return;
	if (tc == dstNameCol)
		return;
	FileHolder		*filePtr = nil;
	filePtr = [fileArray objectAtIndex:row];
	if (filePtr == nil)
		return;
	if (![filePtr conversionDone])
		return;
	//NSLog(@"\t\tclicked show button");
	NSWorkspace		*ws = [NSWorkspace sharedWorkspace];
	[ws
		selectFile:[filePtr convertedFilePath]
		inFileViewerRootedAtPath:nil];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
//	data source/drag and drop methods
- (BOOL) tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pb	{
	if (tv == srcTableView)	{
		NSData		*rowsAsData = [NSKeyedArchiver archivedDataWithRootObject:rows requiringSecureCoding:YES error:nil];
		[pb declareTypes:[NSArray arrayWithObject:@"FileHolderIndexSet"] owner:nil];
		[pb setData:rowsAsData forType:@"FileHolderIndexSet"];
		return YES;
	}
	
	return NO;
}
/*------------------------------------*/
- (NSDragOperation) tableView:(NSTableView *)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op	{
	if (tv == srcTableView)	{
		if (op == 0)
			[tv setDropRow:row dropOperation:1];
		return NSDragOperationMove;
	}
	
	return NSDragOperationNone;
}
/*------------------------------------*/
- (BOOL) tableView:(NSTableView *)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op	{
	NSLog(@"%s",__func__);
	if (tv == srcTableView)	{
		//	if i'm receiving files from the finder
		if ([[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:NSPasteboardTypeFileURL]])	{
			//NSLog(@"\t\treceiving drag from finder");
			int					realInsertionIndex;
			NSArray				*draggedURLArray = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:nil];
			NSMutableArray	*tmpArray = [NSMutableArray arrayWithCapacity:0];
			for (NSURL * draggedURL in draggedURLArray)	{
				[tmpArray addObject:draggedURL.path];
			}
			NSArray				*draggedFileArray = [NSArray arrayWithArray:tmpArray];
			NSMutableArray		*flattenedFileArray = [self flattenFiles:draggedFileArray toDepth:1];
			NSEnumerator		*it;
			NSString			*path;
			FileHolder			*newObj;
			
			//	if the flattened file array is nil (or empty), just return right now
			if ((flattenedFileArray == nil) || ([flattenedFileArray count] < 1))
				return NO;
			//	figure out where i'll be adding the files (-1 for adding to the end)
			realInsertionIndex = row;
			if (realInsertionIndex >= [fileArray count])
				realInsertionIndex = (-1);
			//	run through the flattened file array, adding the contents to the file array
			it = [flattenedFileArray objectEnumerator];
			while (path = [it nextObject])	{
				BOOL		fresh = ![self fileArrayContainsSourcePath:path];
				newObj = [FileHolder createWithPath:path];
				if (newObj != nil)	{
					if (realInsertionIndex == (-1))
						[fileArray addObject:newObj];
					else
						[fileArray insertObject:newObj atIndex:realInsertionIndex];
					if (fresh)
						[self loadCutsFromSidecarForFile:newObj];
				}
			}
			
			//	run through all the files, updating the dst. file names & error strings
			[self updateDstFileNames];
			//	update the table view
			[srcTableView deselectAll:nil];
			[srcTableView reloadData];
			[dstTableView deselectAll:nil];
			[dstTableView reloadData];
			
			return YES;
		}
		//	if i'm receiving a drag from myself (rearranging stuff)
		else if ([[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:@"FileHolderIndexSet"]])	{
			//NSLog(@"\t\treceiving internal drag from self");
			NSData			*rowsAsData = [[info draggingPasteboard] dataForType:@"FileHolderIndexSet"];
			NSIndexSet		*selectedRowIndexes = [NSKeyedUnarchiver unarchivedObjectOfClass:NSIndexSet.class fromData:rowsAsData error:nil];
			NSArray			*selectedRows = [fileArray objectsAtIndexes:selectedRowIndexes];
			NSInteger		realInsertionIndex;
			FileHolder		*nextItem = nil;
			NSEnumerator	*it = nil;
			FileHolder		*anObj = nil;
			
			//	find the item in the array that will be immediately after the dragged rows
			realInsertionIndex = row;
			if (realInsertionIndex == [fileArray count])
				realInsertionIndex = -1;
			else	{
				nextItem = [fileArray objectAtIndex:realInsertionIndex];
				while (([selectedRows containsObject:nextItem]) && (nextItem!=nil))	{
					--realInsertionIndex;
					if (realInsertionIndex >= 0)
						nextItem = [fileArray objectAtIndex:realInsertionIndex];
					else	{
						realInsertionIndex = 0;
						nextItem = nil;
					}
				}
			}
			
			//	remove the objects in the pasteboard from the file array
			[fileArray removeObjectsInArray:selectedRows];
			
			//	if i'm not inserting at the beginning or the end, i need to re-calculate the index because items have been moved
			if ((realInsertionIndex != 0) && (realInsertionIndex != (-1)))
				realInsertionIndex = [fileArray indexOfObject:nextItem];
			
			//	add the objects to the array at the appropriate location
			if (realInsertionIndex == (-1))	{
				it = [selectedRows objectEnumerator];
				while (anObj = [it nextObject])
					[fileArray addObject:anObj];
			}
			else	{
				it = [selectedRows objectEnumerator];
				while (anObj = [it nextObject])
					[fileArray insertObject:anObj atIndex:realInsertionIndex];
			}
			
			//	now go through and update everything
			[self updateDstFileNames];
			[srcTableView deselectAll:nil];
			[srcTableView reloadData];
			[dstTableView deselectAll:nil];
			[dstTableView reloadData];
			
			return YES;
		}
	}
	
	return NO;
}
/*------------------------------------*/
/*
//	delegate methods
- (void) tableView:(NSTableView *)tv didClickTableColumn:(NSTableColumn *)tc	{
	NSSortDescriptor		*descriptor;
	NSArray					*descriptorArray;
	
	//	made the sort descriptor based on which column i clicked on
	if (tc == sourceNameCol)	{
		descriptor = [[[NSSortDescriptor alloc]
			initWithKey:@"srcFileName"
			ascending:YES
			selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	else if (tc == destNameCol)	{
		descriptor = [[[NSSortDescriptor alloc]
			initWithKey:@"dstFileName"
			ascending:YES
			selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	else if (tc == statusCol)	{
		descriptor = [[[NSSortDescriptor alloc]
			initWithKey:@"errorString"
			ascending:YES
			selector:@selector(caseInsensitiveCompare:)] autorelease];
	}
	//	if i couldn't make a descriptor, bail
	if (descriptor == nil)
		return;
	//	actually sort the array, reload the table
	descriptorArray = [NSArray arrayWithObject:descriptor];
	[fileArray sortUsingDescriptors:descriptorArray];
	[tv reloadData];
}
 */
/*------------------------------------*/
- (void) tableView:(NSTableView *)tv deleteRowIndexes:(NSIndexSet *)i	{
	//NSLog(@"%s",__func__);
	//	return immediately if i was passed a nil or empty index set
	if ((i == nil) || ([i count] < 1))
		return;
	if (tv == srcTableView)	{
		//	capture which sources are losing entries so we can refresh their sidecars
		NSMutableSet	*affectedPaths = [NSMutableSet setWithCapacity:[i count]];
		[i enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop){
			if (idx < [self->fileArray count])	{
				FileHolder	*f = [self->fileArray objectAtIndex:idx];
				NSString	*p = [f fullSrcPath];
				if (p != nil)
					[affectedPaths addObject:p];
			}
		}];
		//	remove the items from the file array, reload the table
		[fileArray removeObjectsAtIndexes:i];
		[self updateDstFileNames];
		[srcTableView deselectAll:nil];
		[dstTableView deselectAll:nil];
		[srcTableView reloadData];
		[dstTableView reloadData];
		for (NSString *p in affectedPaths)
			[self persistSidecarForSourcePath:p];
	}
}
/*------------------------------------*/
- (NSCell *) tableView:(NSTableView *)tv dataCellForTableColumn:(NSTableColumn *)tc row:(NSInteger)row	{
	//NSLog(@"\t\t%@, %@, %ld",tv, tc, row);
	//	if this is the source table, just return the default data cell
	if (tv == srcTableView)	{
		//return [tc dataCellForRow:row];
		FileHolder		*filePtr = [fileArray objectAtIndex:row];
		NSCell			*returnMe = [tc dataCellForRow:row];
		if ([filePtr srcFileExists])
			[(NSTextFieldCell *)returnMe setTextColor:[NSColor textColor]];
		else
			[(NSTextFieldCell *)returnMe setTextColor:[NSColor disabledControlTextColor]];
	}
	//	if this is the destination table view, i'll be returning one of a number of cells
	else if (tv == dstTableView)	{
		if (tc == nil)
			return nil;
		else if (tc == dstNameCol)
			return [tc dataCellForRow:row];
		else	{
			FileHolder			*filePtr = [fileArray objectAtIndex:row];
			//	if i'm done converting the file, return the "open clip" button cell
			if ([filePtr conversionDone])	{
				return statusColButtonCell;
			}
			//	if i'm not done converting the file, return the standard text field cell
			else	{
				if ([filePtr errorString]!=nil)
					[statusColTxtFieldCell setTextColor:[NSColor redColor]];
				else	{
					if ([[filePtr statusString] isEqualToString:@"Ready"])
						[statusColTxtFieldCell setTextColor:[NSColor greenColor]];
					else
						[statusColTxtFieldCell setTextColor:[NSColor redColor]];
				}
				return statusColTxtFieldCell;
			}
		}
	}
	
	return [tc dataCellForRow:row];
}
/* --------------------------------------------------------------------------------- */
#pragma mark ---------------------
/* --------------------------------------------------------------------------------- */
- (NSMutableArray *) fileArray	{
	return fileArray;
}


- (FileHolder *) firstFile	{
	if (fileArray == nil)
		return nil;
	if ([fileArray count]<1)
		return nil;
	return [fileArray objectAtIndex:0];
}
- (FileHolder *) selectedFile	{
	if (fileArray == nil)
		return nil;
	NSInteger			selectedRow = [srcTableView selectedRow];
	if (selectedRow < 0)
		return nil;
	if (selectedRow >= [fileArray count])
		return nil;
	return [fileArray objectAtIndex:selectedRow];
}

/* --------------------------------------------------------------------------------- */
#pragma mark --------------------- timeline / cuts
/* --------------------------------------------------------------------------------- */
- (void) srcTableDoubleClicked:(id)sender	{
	NSInteger		clickedRow = [srcTableView clickedRow];
	if (clickedRow < 0)
		clickedRow = [srcTableView selectedRow];
	if (clickedRow < 0 || clickedRow >= (NSInteger)[fileArray count])
		return;
	FileHolder		*f = [fileArray objectAtIndex:clickedRow];
	if (f == nil)
		return;
	[TimelineWindowController showForFile:f fileListController:self];
}

- (void) addCutForSourcePath:(NSString *)path timeRange:(CMTimeRange)r	{
	[self addCutForSourcePath:path timeRange:r label:nil];
}

- (void) addCutForSourcePath:(NSString *)path timeRange:(CMTimeRange)r label:(NSString *)userLabel	{
	if (path == nil)
		return;
	//	pick an insertion index right after the last existing entry that shares this source
	NSInteger		insertAfter = -1;
	for (NSInteger i = 0; i < (NSInteger)[fileArray count]; ++i)	{
		FileHolder	*f = [fileArray objectAtIndex:i];
		if ([[f fullSrcPath] isEqualToString:path])
			insertAfter = i;
	}

	FileHolder		*cut = [FileHolder createWithPath:path];
	if (cut == nil)
		return;
	cut.inTime = r.start;
	cut.outTime = CMTimeRangeGetEnd(r);
	cut.cutLabel = [self normalizedUniqueLabel:userLabel forSourcePath:path excludingFile:nil];

	if (insertAfter >= 0 && (insertAfter+1) < (NSInteger)[fileArray count])
		[fileArray insertObject:cut atIndex:(insertAfter+1)];
	else
		[fileArray addObject:cut];

	[self updateDstFileNames];
	[srcTableView reloadData];
	[dstTableView reloadData];
	[self persistSidecarForSourcePath:path];
}

- (void) fileHolderRangeChanged:(FileHolder *)f	{
	//	the dst name doesn't depend on the range, but other consumers may want to refresh
	[self updateDstFileNames];
	[srcTableView reloadData];
	[dstTableView reloadData];
	if (f != nil)
		[self persistSidecarForSourcePath:[f fullSrcPath]];
}

- (void) updateLabel:(NSString *)userLabel forFileHolder:(FileHolder *)f	{
	if (f == nil)
		return;
	//	originals (no existing label) keep their natural name- ignore label edits for them
	if ([[f cutLabel] length] == 0)
		return;
	NSString		*newLabel = [self normalizedUniqueLabel:userLabel forSourcePath:[f fullSrcPath] excludingFile:f];
	if (newLabel == nil || [newLabel isEqualToString:[f cutLabel]])
		return;
	[f setCutLabel:newLabel];
	[self updateDstFileNames];
	[srcTableView reloadData];
	[dstTableView reloadData];
	[self persistSidecarForSourcePath:[f fullSrcPath]];
}

- (NSString *) normalizedUniqueLabel:(NSString *)userLabel forSourcePath:(NSString *)path excludingFile:(FileHolder *)excludeFile	{
	NSString	*trimmed = [userLabel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] == 0)	{
		//	auto-number: pick max existing _NNN for this source and add one
		NSInteger	maxIndex = 1;
		for (FileHolder *f in fileArray)	{
			if (f == excludeFile)
				continue;
			if (![[f fullSrcPath] isEqualToString:path])
				continue;
			NSString	*lbl = [f cutLabel];
			if ([lbl length] > 1 && [lbl characterAtIndex:0] == '_')	{
				NSScanner	*s = [NSScanner scannerWithString:[lbl substringFromIndex:1]];
				NSInteger	n = 0;
				if ([s scanInteger:&n] && n > maxIndex)
					maxIndex = n;
			}
		}
		return [NSString stringWithFormat:@"_%03ld", (long)(maxIndex + 1)];
	}
	//	the label is appended verbatim before the extension, so prepend a separator
	//	if the user didn't already supply one (so "intro" -> "_intro")
	NSString	*base = trimmed;
	unichar		first = [base characterAtIndex:0];
	if (first != '_' && first != '-')
		base = [@"_" stringByAppendingString:base];
	//	uniquify against other cuts of the same source by appending -2, -3, ...
	NSString	*candidate = base;
	NSInteger	suffix = 2;
	while ([self labelConflict:candidate sourcePath:path excludingFile:excludeFile])	{
		candidate = [NSString stringWithFormat:@"%@-%ld", base, (long)suffix++];
	}
	return candidate;
}

- (BOOL) labelConflict:(NSString *)label sourcePath:(NSString *)path excludingFile:(FileHolder *)excludeFile	{
	for (FileHolder *f in fileArray)	{
		if (f == excludeFile)
			continue;
		if (![[f fullSrcPath] isEqualToString:path])
			continue;
		if ([[f cutLabel] isEqualToString:label])
			return YES;
	}
	return NO;
}

/* --------------------------------------------------------------------------------- */
#pragma mark --------------------- sidecar persistence
/* --------------------------------------------------------------------------------- */
//	the sidecar lives next to the source as "<source-with-ext>.cuts.json".
//	keeping the source extension means clip.mov and clip.mp4 don't collide.
- (NSString *) sidecarPathForSourcePath:(NSString *)path	{
	if (path == nil)
		return nil;
	return [path stringByAppendingPathExtension:@"cuts.json"];
}

- (BOOL) fileArrayContainsSourcePath:(NSString *)path	{
	if (path == nil)
		return NO;
	for (FileHolder *f in fileArray)	{
		if ([[f fullSrcPath] isEqualToString:path])
			return YES;
	}
	return NO;
}

//	gather every FileHolder for `path`, write a sidecar describing the non-default
//	original range and any cut entries. if there's nothing worth persisting, the
//	sidecar is removed instead.
- (void) persistSidecarForSourcePath:(NSString *)path	{
	if (path == nil)
		return;
	NSString		*sidecar = [self sidecarPathForSourcePath:path];
	NSFileManager	*fm = [NSFileManager defaultManager];

	NSMutableArray	*entries = [NSMutableArray arrayWithCapacity:0];
	for (FileHolder *f in fileArray)	{
		if (![[f fullSrcPath] isEqualToString:path])
			continue;
		//	the unlabeled "original" only persists if the user gave it a custom range
		BOOL		isLabeled = ([[f cutLabel] length] > 0);
		if (!isLabeled && ![f isCut])
			continue;
		NSMutableDictionary	*entry = [NSMutableDictionary dictionaryWithCapacity:3];
		entry[@"cutLabel"] = isLabeled ? [f cutLabel] : @"";
		if (CMTIME_IS_VALID([f inTime]))	{
			entry[@"in"] = @{ @"value": @([f inTime].value), @"timescale": @([f inTime].timescale) };
		}
		if (CMTIME_IS_VALID([f outTime]))	{
			entry[@"out"] = @{ @"value": @([f outTime].value), @"timescale": @([f outTime].timescale) };
		}
		[entries addObject:entry];
	}

	if ([entries count] == 0)	{
		if ([fm fileExistsAtPath:sidecar])	{
			NSError		*rmErr = nil;
			if (![fm removeItemAtPath:sidecar error:&rmErr])
				NSLog(@"WARN: could not remove %@: %@",sidecar,rmErr);
		}
		return;
	}

	NSDictionary	*root = @{ @"version": @1, @"entries": entries };
	NSError			*err = nil;
	NSData			*data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&err];
	if (data == nil)	{
		NSLog(@"ERR: serializing sidecar for %@: %@",path,err);
		return;
	}
	if (![data writeToFile:sidecar atomically:YES])	{
		//	the source's directory may be read-only- log and move on; the in-app state still works
		NSLog(@"WARN: could not write cut sidecar at %@",sidecar);
	}
}

//	called once per freshly-imported source. reads its sidecar (if any) and applies the
//	saved original range to `freshFile`, then inserts cut FileHolders right after it.
- (void) loadCutsFromSidecarForFile:(FileHolder *)freshFile	{
	if (freshFile == nil)
		return;
	NSString		*path = [freshFile fullSrcPath];
	NSString		*sidecar = [self sidecarPathForSourcePath:path];
	NSFileManager	*fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:sidecar])
		return;
	NSData			*data = [NSData dataWithContentsOfFile:sidecar];
	if (data == nil)
		return;
	NSError			*err = nil;
	id				obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
	if (![obj isKindOfClass:[NSDictionary class]])
		return;
	NSArray			*entries = [(NSDictionary *)obj objectForKey:@"entries"];
	if (![entries isKindOfClass:[NSArray class]])
		return;

	NSInteger		anchor = [fileArray indexOfObject:freshFile];
	if (anchor == NSNotFound)
		return;
	NSInteger		nextInsert = anchor + 1;

	for (NSDictionary *e in entries)	{
		if (![e isKindOfClass:[NSDictionary class]])
			continue;
		NSString	*label = e[@"cutLabel"];
		if (![label isKindOfClass:[NSString class]])
			label = @"";
		CMTime		inT = kCMTimeInvalid;
		CMTime		outT = kCMTimeInvalid;
		NSDictionary *inD = e[@"in"];
		NSDictionary *outD = e[@"out"];
		if ([inD isKindOfClass:[NSDictionary class]])	{
			int64_t	v = [[inD objectForKey:@"value"] longLongValue];
			int32_t	s = [[inD objectForKey:@"timescale"] intValue];
			if (s > 0) inT = CMTimeMake(v, s);
		}
		if ([outD isKindOfClass:[NSDictionary class]])	{
			int64_t	v = [[outD objectForKey:@"value"] longLongValue];
			int32_t	s = [[outD objectForKey:@"timescale"] intValue];
			if (s > 0) outT = CMTimeMake(v, s);
		}

		if ([label length] == 0)	{
			//	no label = restore the original FileHolder's custom range
			[freshFile setInTime:inT];
			[freshFile setOutTime:outT];
		}
		else	{
			FileHolder	*cut = [FileHolder createWithPath:path];
			if (cut == nil)
				continue;
			[cut setCutLabel:label];
			[cut setInTime:inT];
			[cut setOutTime:outT];
			[fileArray insertObject:cut atIndex:nextInsert++];
		}
	}
}


@end
