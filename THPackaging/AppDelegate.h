//
//  AppDelegate.h
//  THPackaging
//
//  Created by Hao Tang on 14-1-20.
//

#import <Cocoa/Cocoa.h>
#import "IRTextFieldDrag.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
@private
    NSWindow *_window;
    NSUserDefaults *_defaults;
    
    NSTask *_unzipTask;
    NSTask *_provisioningTask;
    NSTask *_codesignTask;
    NSTask *_verifyTask;
    NSTask *_zipTask;
    NSString *_originalIpaPath;
    NSString *_appPath;
    NSString *_workingPath;
    NSString *_outputPath;
    NSString *_appName;
    NSString *_fileName;
    
    NSString *_codesigningResult;
    NSString *_verificationResult;
    
    IBOutlet IRTextFieldDrag *_pathField;
    IBOutlet IRTextFieldDrag *_provisioningPathField;
    IBOutlet IRTextFieldDrag *_entitlementField;
    IBOutlet IRTextFieldDrag *_channelPathField;
    IBOutlet IRTextFieldDrag *_bundleIDField;
    IBOutlet NSButton    *_browseButton;
    IBOutlet NSButton    *_provisioningBrowseButton;
    IBOutlet NSButton *_entitlementBrowseButton;
    IBOutlet NSButton *_channelBrowseButton;
    IBOutlet NSButton    *_packagingButton;
    IBOutlet NSButton *_openOutputButton;
    IBOutlet NSTextField *_statusLabel;
    IBOutlet NSProgressIndicator *_flurry;
    IBOutlet NSButton *_changeBundleIDCheckbox;
    
    IBOutlet NSComboBox *_certComboBox;
    NSArray *_certComboBoxItems;
    NSTask *_certTask;
    NSArray *_getCertsResult;
    
    NSArray *_channelArray;
    NSInteger _currentZipTaskIndex;
}

@property (assign) IBOutlet NSWindow *window;

- (IBAction)packaging:(id)sender;
- (IBAction)browse:(id)sender;
- (IBAction)provisioningBrowse:(id)sender;
- (IBAction)channelBrowse:(id)sender;
- (IBAction)entitlementBrowse:(id)sender;
- (IBAction)showHelp:(id)sender;
- (IBAction)changeBundleIDPressed:(id)sender;
- (IBAction)openOutputDirectory:(id)sender;
- (IBAction)closeButtonClicked:(id)sender;
- (IBAction)minimizeButtonClocked:(id)sender;

@end
