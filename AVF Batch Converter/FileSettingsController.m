#import "FileSettingsController.h"
#import "ExportController.h"
#import "VVAVFTranscoder.h"




@implementation FileSettingsController


- (id) init	{
	self = [super init];
	if (self!=nil)	{
	}
	return self;
}
- (void) awakeFromNib	{
	//	load the saved settings from the user defaults (populates the pop-up button)
	[self loadSavedSettingsFromDefaults];
	//	load the last audio/video settings
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	//NSDictionary		*tmpDict = nil;

	NSDictionary		*tmpAudioDict = [def objectForKey:@"lastAudioSettings"];
	if (tmpAudioDict==nil)
		tmpAudioDict = [NSDictionary dictionary];

	NSDictionary		*tmpVideoDict = [def objectForKey:@"lastVideoSettings"];
	if (tmpVideoDict==nil)
		tmpVideoDict = [NSDictionary dictionary];
	exportController.videoSettingsDict = tmpVideoDict;

	//	derive the toggle's initial state from the persisted dict's strip flag,
	//	then push the toggle-respecting effective dict back to the export controller
	[self syncIncludeAudioToggleToDict:tmpAudioDict];
	[self applyAudioDict:tmpAudioDict videoDict:tmpVideoDict];

	if (tmpAudioDict == nil && tmpVideoDict == nil)	{
		[loadSavedExportSettingsPUB selectItemWithTitle:@"h264"];
		[self loadSavedExportSettingsPUBUsed:loadSavedExportSettingsPUB];
	}
	else	{
		[loadSavedExportSettingsPUB selectItem:nil];
	}
}

//	YES if the toggle is on (audio should be included). Defaults to YES if the toggle
//	hasn't been wired up yet (we haven't reached awakeFromNib).
- (BOOL) includeAudio	{
	if (includeAudioToggle == nil)
		return YES;
	return [includeAudioToggle state] == NSControlStateValueOn;
}

//	read the strip key out of `d` and reflect it on the toggle, so loading a preset
//	that already encodes "no audio" pre-checks the checkbox correctly
- (void) syncIncludeAudioToggleToDict:(NSDictionary *)d	{
	if (includeAudioToggle == nil)
		return;
	NSNumber	*stripNum = [d objectForKey:kVVAVFTranscodeStripMediaKey];
	BOOL		strip = (stripNum != nil && [stripNum boolValue]);
	[includeAudioToggle setState:(strip ? NSControlStateValueOff : NSControlStateValueOn)];
}

//	return a copy of `d` with the strip key set or removed to match the toggle's
//	current state. nil-safe (treats nil as empty dict).
- (NSDictionary *) audioDictApplyingToggle:(NSDictionary *)d	{
	NSMutableDictionary		*m = (d != nil) ? [d mutableCopy] : [NSMutableDictionary dictionary];
	if ([self includeAudio])
		[m removeObjectForKey:kVVAVFTranscodeStripMediaKey];
	else
		[m setObject:@YES forKey:kVVAVFTranscodeStripMediaKey];
	return m;
}

//	push the effective audio + raw video dicts to the ExportController and refresh
//	the descriptions on the main window. centralizes the "audio side effect" so
//	preset / sheet / toggle paths all behave consistently.
- (void) applyAudioDict:(NSDictionary *)audio videoDict:(NSDictionary *)video	{
	NSDictionary	*effectiveAudio = [self audioDictApplyingToggle:audio];
	exportController.audioSettingsDict = effectiveAudio;
	if (video != nil)
		exportController.videoSettingsDict = video;

	NSDictionary	*usedVideo = (video != nil) ? video : exportController.videoSettingsDict;
	AVFExportAVSettingsWindow	*tmpWin = [AVFExportAVSettingsWindow createWithAudioSettings:effectiveAudio videoSettings:usedVideo];
	NSString		*audioDesc = tmpWin.audioVC.lengthyDescription;
	if (audioDesc == nil) audioDesc = @"";
	if (![self includeAudio])
		audioDesc = @"Audio: stripped from output";
	NSString		*videoDesc = tmpWin.videoVC.lengthyDescription;
	if (videoDesc == nil) videoDesc = @"";
	[audioDescriptionField setStringValue:audioDesc];
	[videoDescriptionField setStringValue:videoDesc];

	NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
	[def setObject:effectiveAudio forKey:@"lastAudioSettings"];
	if (video != nil)
		[def setObject:video forKey:@"lastVideoSettings"];
}

- (IBAction) includeAudioToggleUsed:(id)sender	{
	//	re-derive the effective audio dict from whatever's currently in defaults
	//	(strip key removed so the toggle is the source of truth), then push.
	NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
	NSDictionary	*current = [def objectForKey:@"lastAudioSettings"];
	NSMutableDictionary	*raw = (current != nil) ? [current mutableCopy] : [NSMutableDictionary dictionary];
	[raw removeObjectForKey:kVVAVFTranscodeStripMediaKey];
	[self applyAudioDict:raw videoDict:nil];
}

- (void) loadSavedSettingsFromDefaults	{
	//	populate the saved settings pop-up button
	[loadSavedExportSettingsPUB removeAllItems];
	NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
	NSDictionary		*savedSettings = [def objectForKey:@"savedExportSettings"];
	//	if the saved settings are nil or empty, populate them with a few default settings
	if (savedSettings==nil || [savedSettings count]<1)	{
		savedSettings = @{
			@"h264": @{
				@"audio":@{
					AVFormatIDKey: @1633772320,
					AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Variable
				},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeH264,
					kVVAVFTranscodeMultiPassEncodeKey: @1,
					AVVideoCompressionPropertiesKey: @{
						AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
					}
				}
			},
			@"Hap": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHap,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"Hap Alpha": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHapAlpha,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"Hap Q": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHapQ,
				}
			},
			
			@"Hap 7 Alpha": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHap7Alpha,
				}
			},
			/*
			@"Hap HDR": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecHapHDR,
					AVVideoCompressionPropertiesKey: @{
						AVHapVideoHDRSignedFloatKey: @NO
					}
				}
			},
			*/
			@"PJPEG": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeJPEG,
					AVVideoCompressionPropertiesKey: @{
						AVVideoQualityKey: @0.76
					}
				}
			},
			@"ProRes 422": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeAppleProRes422,
				}
			},
			@"ProRes 4444": @{
				@"audio":@{},
				@"video":@{
					AVVideoCodecKey: AVVideoCodecTypeAppleProRes4444,
				}
			}
		};
		[def setObject:savedSettings forKey:@"savedExportSettings"];
		[def synchronize];
		savedSettings = [def objectForKey:@"savedExportSettings"];
	}
	
	//	run through and populate the pop-up button with the saved settings
	NSArray				*sortedSettingKeys = nil;
	sortedSettingKeys = [[savedSettings allKeys] sortedArrayUsingComparator:^(id obj1, id obj2)	{
		return [obj1 compare:obj2];
	}];
	NSMenu				*settingsMenu = [loadSavedExportSettingsPUB menu];
	for (NSString *tmpKey in sortedSettingKeys)	{
		NSDictionary		*settingsDict = [savedSettings objectForKey:tmpKey];
		if (settingsDict!=nil)	{
			//	each saved setting menu item contains the dict
			NSMenuItem		*newItem = [[NSMenuItem alloc] initWithTitle:tmpKey action:nil keyEquivalent:@""];
			[newItem setRepresentedObject:settingsDict];
			[settingsMenu addItem:newItem];
			newItem = nil;
		}
	}
	
	//	copy all the items in the load settings pop-up button to the delete settings pop-up button
	{
		NSMenu		*loadMenu = [loadSavedExportSettingsPUB menu];
		NSMenu		*deleteMenu = [deleteSavedExportSettingsPUB menu];
		[deleteMenu removeAllItems];
		for (NSMenuItem *itemPtr in [loadMenu itemArray])	{
			NSMenuItem		*itemCopy = [itemPtr copy];
			if (itemCopy!=nil)
				[deleteMenu addItem:itemCopy];
		}
		[deleteSavedExportSettingsPUB selectItem:nil];
	}
}

- (IBAction) settingsButtonClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	NSUserDefaults		*tmpDef = [NSUserDefaults standardUserDefaults];
	
	AVFExportAVSettingsWindow		*win = [AVFExportAVSettingsWindow
		createWithAudioSettings:[tmpDef objectForKey:@"lastAudioSettings"]
		videoSettings:[tmpDef objectForKey:@"lastVideoSettings"]];
	
	if (win != nil)	{
		//	open the win!
		[mainWindow
			beginSheet:win.window
			completionHandler:^(NSModalResponse returnCode)	{
				NSDictionary		*audioDict = [win.audioVC createAVFSettingsDict];
				NSDictionary		*videoDict = [win.videoVC createAVFSettingsDict];

				[self->loadSavedExportSettingsPUB selectItem:nil];
				if (returnCode != NSModalResponseOK)	{
					return;
				}

				//	the audio sheet doesn't manage the strip key; let the toggle apply it.
				//	this also handles persistence and label refresh.
				[self applyAudioDict:audioDict videoDict:videoDict];
			}];
	}
	
}
- (IBAction) loadSavedExportSettingsPUBUsed:(id)sender	{
	//NSLog(@"%s",__func__);
	NSMenuItem			*selItem = [sender selectedItem];
	if (selItem==nil)
		return;
	NSDictionary		*settingsDict = [selItem representedObject];
	if (settingsDict==nil)
		return;
	NSDictionary		*audio = [settingsDict objectForKey:@"audio"];
	NSDictionary		*video = [settingsDict objectForKey:@"video"];

	//	if the preset already encodes a strip preference, surface it on the toggle
	[self syncIncludeAudioToggleToDict:audio];
	[self applyAudioDict:audio videoDict:video];
}
- (IBAction) saveCurrentSettingsClicked:(id)sender	{
	//NSLog(@"%s",__func__);
	[mainWindow beginCriticalSheet:saveSettingsWindow completionHandler:^(NSModalResponse returnCode)	{
		//	if i didn't save a setting, i'm not returning a 'continue'
		if (returnCode==NSModalResponseContinue)	{
		}
	}];
}
- (IBAction) deleteSettingClicked:(id)sender	{
	NSString		*deleteTitle = [deleteSavedExportSettingsPUB titleOfSelectedItem];
	if (deleteTitle!=nil)	{
		NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
		NSDictionary		*savedSettings = [def objectForKey:@"savedExportSettings"];
		if (savedSettings!=nil)	{
			NSMutableDictionary		*mutSavedSettings = [savedSettings mutableCopy];
			if (mutSavedSettings!=nil)	{
				[mutSavedSettings removeObjectForKey:deleteTitle];
				[def setObject:mutSavedSettings forKey:@"savedExportSettings"];
				[def synchronize];
				
				//	reload the saved export settings
				[self loadSavedSettingsFromDefaults];
				
				mutSavedSettings = nil;
			}
		}
	}
}
- (IBAction) cancelSaveSettingsClicked:(id)sender	{
	[mainWindow endSheet:saveSettingsWindow returnCode:NSModalResponseAbort];
}
- (IBAction) proceedSaveSettingsClicked:(id)sender	{
	NSString		*presetName = [saveSettingsField stringValue];
	if (presetName!=nil && [presetName length]>0 && [loadSavedExportSettingsPUB itemWithTitle:presetName]==nil)	{
		//	assemble the dict that contains other dicts which describe the audio & video settings
		NSMutableDictionary		*newSettingsDict = [NSMutableDictionary dictionaryWithCapacity:0];
		NSDictionary		*tmpDict = nil;
		tmpDict = exportController.videoSettingsDict;
		if (tmpDict!=nil)
			[newSettingsDict setObject:tmpDict forKey:@"video"];
		tmpDict = exportController.audioSettingsDict;
		if (tmpDict!=nil)
			[newSettingsDict setObject:tmpDict forKey:@"audio"];
		
		//	save stuff in the default
		NSUserDefaults		*def = [NSUserDefaults standardUserDefaults];
		NSDictionary		*settings = [def objectForKey:@"savedExportSettings"];
		NSMutableDictionary	*tmpMutDict = (settings==nil) ? [NSMutableDictionary dictionaryWithCapacity:0] : [settings mutableCopy];
		[tmpMutDict setObject:newSettingsDict forKey:presetName];
		[def setObject:tmpMutDict forKey:@"savedExportSettings"];
		[def synchronize];
		//NSLog(@"\t\tsaving settings %@",newSettingsDict);
		
		//	reset/reload the various UI items
		[saveSettingsField setStringValue:@""];
		[mainWindow endSheet:saveSettingsWindow returnCode:NSModalResponseContinue];
		//	reload the saved settings pop-up button regardless
		dispatch_async(dispatch_get_main_queue(), ^{
			[self loadSavedSettingsFromDefaults];
		});
	}
}


@end
