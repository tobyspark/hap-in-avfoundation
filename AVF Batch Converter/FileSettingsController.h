#import <Foundation/Foundation.h>
#import "AVFExportAVSettingsWindow.h"

@class ExportController;


@interface FileSettingsController : NSObject	{
	IBOutlet ExportController		*exportController;

	IBOutlet NSWindow				*mainWindow;

	IBOutlet NSTextField			*videoDescriptionField;
	IBOutlet NSTextField			*audioDescriptionField;
	IBOutlet NSPopUpButton			*loadSavedExportSettingsPUB;
	IBOutlet NSPopUpButton			*deleteSavedExportSettingsPUB;

	IBOutlet NSWindow				*saveSettingsWindow;
	IBOutlet NSTextField			*saveSettingsField;

    IBOutlet NSButton				*includeAudioToggle;
}

- (void) loadSavedSettingsFromDefaults;

- (IBAction) settingsButtonClicked:(id)sender;
- (IBAction) loadSavedExportSettingsPUBUsed:(id)sender;

- (IBAction) saveCurrentSettingsClicked:(id)sender;
- (IBAction) deleteSettingClicked:(id)sender;
- (IBAction) cancelSaveSettingsClicked:(id)sender;
- (IBAction) proceedSaveSettingsClicked:(id)sender;

- (IBAction) includeAudioToggleUsed:(id)sender;

@end
