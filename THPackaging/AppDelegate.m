//
//  AppDelegate.m
//  THPackaging
//
//  Created by Hao Tang on 14-1-20.
//

#import "AppDelegate.h"

static NSString *kKeyPrefsBundleIDChange        = @"keyBundleIDChange";

static NSString *kKeyBundleIDPlistApp           = @"CFBundleIdentifier";
static NSString *kKeyBundleIDPlistiTunesArtwork = @"softwareVersionBundleId";

static NSString *kUnzippedIPAPath               = @"UnzippedIPAPath";
static NSString *kPayloadDirName                = @"Payload";
static NSString *kInfoPlistFilename             = @"Info.plist";

static NSString *kChannelFileName               = @"channel.txt";
static NSString *kTHPackagingOutput             = @"THPackagingOutput";

static NSString *kChannelNumberKey              = @"ChannelNumber";
static NSString *kChannelNameKey                = @"ChannelName";
static NSString *kOriginalIPAPathKey               = @"ORIGINAL_IPA_PATH";
static NSString *kEntitlementPathKey               = @"ENTITLEMENT_PATH";
static NSString *kMobileProvisionPathKey           = @"MOBILEPROVISION_PATH";
static NSString *kChannelPathKey                   = @"CHANNEL_PATH";
static NSString *kCertIndexKey                     = @"CERT_INDEX";

@implementation AppDelegate

@synthesize window = _window;

#pragma mark - Application Lifcycle

- (void)dealloc {
    [_certComboBoxItems release];
    [_channelArray release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [_flurry setAlphaValue:0.5];
    _outputPath = @"";
    [self enableControls];
    
    _defaults = [NSUserDefaults standardUserDefaults];
    
    // Look up available signing certificates
    [self getCerts];
    
    if ([_defaults valueForKey:kOriginalIPAPathKey]) {
        [_pathField setStringValue:[_defaults valueForKey:kOriginalIPAPathKey]];
    }
    
    if ([_defaults valueForKey:kEntitlementPathKey]) {
        [_entitlementField setStringValue:[_defaults valueForKey:kEntitlementPathKey]];
    }
    
    if ([_defaults valueForKey:kMobileProvisionPathKey]) {
        [_provisioningPathField setStringValue:[_defaults valueForKey:kMobileProvisionPathKey]];
    }
    
    if ([_defaults valueForKey:kChannelPathKey]) {
        [_channelPathField setStringValue:[_defaults valueForKey:kChannelPathKey]];
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/zip"]) {
        NSRunAlertPanel(@"Error", 
                        @"This app cannot run without the zip utility present at /usr/bin/zip",
                        @"OK",nil,nil);
        exit(0);
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/unzip"]) {
        NSRunAlertPanel(@"Error", 
                        @"This app cannot run without the unzip utility present at /usr/bin/unzip",
                        @"OK",nil,nil);
        exit(0);
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/codesign"]) {
        NSRunAlertPanel(@"Error", 
                        @"This app cannot run without the codesign utility present at /usr/bin/codesign",
                        @"OK",nil, nil);
        exit(0);
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [_window makeKeyAndOrderFront:self];
    return YES;
}

#pragma mark - Actions

- (IBAction)packaging:(id)sender {
    //Save cert name
    [_defaults setValue:[_pathField stringValue] forKey:kOriginalIPAPathKey];
    [_defaults setValue:[NSNumber numberWithInteger:[_certComboBox indexOfSelectedItem]] forKey:kCertIndexKey];
    [_defaults setValue:[_entitlementField stringValue] forKey:kEntitlementPathKey];
    [_defaults setValue:[_provisioningPathField stringValue] forKey:kMobileProvisionPathKey];
    [_defaults setValue:[_channelPathField stringValue] forKey:kChannelPathKey];
    [_defaults setValue:[_bundleIDField stringValue] forKey:kKeyPrefsBundleIDChange];
    [_defaults synchronize];
    
    _codesigningResult = nil;
    _verificationResult = nil;
    
    _originalIpaPath = [[_pathField stringValue] retain];
    _workingPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"com.haotang.thpackaging"] retain];
    
    if ([_certComboBox objectValue]) {
        if ([[[_originalIpaPath pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
            [self disableControls];
            
            NSLog(@"Setting up working directory in %@",_workingPath);
            [_statusLabel setHidden:NO];
            [_statusLabel setStringValue:@"Setting up working directory"];
            
            [[NSFileManager defaultManager] removeItemAtPath:_workingPath error:nil];
            
            [[NSFileManager defaultManager] createDirectoryAtPath:_workingPath withIntermediateDirectories:TRUE attributes:nil error:nil];
            [self doUnzip];
        } else {
            NSRunAlertPanel(_(@"Error"),
                            _(@"You must choose an *.ipa file"),
                            @"OK",nil,nil);
            [self enableControls];
            [_statusLabel setStringValue:_(@"Please try again")];
        }
    } else {
        NSRunAlertPanel(_(@"Error"),
                        _(@"You must choose an signing certificate from dropdown."),
                        @"OK",nil,nil);
        [self enableControls];
        [_statusLabel setStringValue:_(@"Please try again")];
    }
}

- (IBAction)browse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[ @"ipa" ]];
    
    if ( [openDlg runModal] == NSOKButton )
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [_pathField setStringValue:fileNameOpened];
    }
}

- (IBAction)provisioningBrowse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[ @"mobileprovision" ]];

    if ( [openDlg runModal] == NSOKButton )
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [_provisioningPathField setStringValue:fileNameOpened];
    }
}

- (IBAction)channelBrowse:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setAllowsOtherFileTypes:NO];
    [openPanel setAllowedFileTypes:@[ @"txt", @"data" ]];

    if ([openPanel runModal] == NSOKButton) {
        NSString *fileNameOpened = [[[openPanel URLs] objectAtIndex:0] path];
        [_channelPathField setStringValue:fileNameOpened];
    }
}

- (IBAction)entitlementBrowse:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[ @"plist" ]];

    if ( [openDlg runModal] == NSOKButton )
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [_entitlementField setStringValue:fileNameOpened];
    }
}

- (IBAction)showHelp:(id)sender {
    NSRunAlertPanel(@"打包，就是这么简单，THPackaging，你值得拥有",
                    @"",
                    @"OK",nil, nil);
}

- (IBAction)changeBundleIDPressed:(id)sender {
    
    if (sender != _changeBundleIDCheckbox) {
        return;
    }
    
    _bundleIDField.enabled = _changeBundleIDCheckbox.state == NSOnState;
}

- (void)openOutputDirectory:(id)sender {
    NSTask *openTask = [[[NSTask alloc] init] autorelease];
    [openTask setLaunchPath:@"/usr/bin/open"];
    [openTask setArguments:@[ _outputPath ]];
    [openTask launch];
}

- (IBAction)closeButtonClicked:(id)sender {
    [[NSApp mainWindow] performClose:nil];
}

- (IBAction)minimizeButtonClocked:(id)sender {
    [[NSApp mainWindow] performMiniaturize:nil];
}

#pragma mark - Get certs process

- (void)getCerts {
    
    _getCertsResult = nil;
    
    NSLog(@"Getting Certificate IDs");
    [_statusLabel setStringValue:_(@"Getting Signing Certificate IDs")];
    
    _certTask = [[NSTask alloc] init];
    [_certTask setLaunchPath:@"/usr/bin/security"];
    [_certTask setArguments:[NSArray arrayWithObjects:@"find-identity", @"-v", @"-p", @"codesigning", nil]];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCerts:) userInfo:nil repeats:TRUE];
    
    NSPipe *pipe=[NSPipe pipe];
    [_certTask setStandardOutput:pipe];
    [_certTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [_certTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchGetCerts:) toTarget:self withObject:handle];
}

- (void)watchGetCerts:(NSFileHandle*)streamHandle {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    
    NSString *securityResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    
    NSArray *rawResult = [securityResult componentsSeparatedByString:@"\""];
    [securityResult release];
    
    NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity:20];
    for (int i = 0; i <= [rawResult count] - 2; i+=2) {
        
        NSLog(@"i:%d", i+1);
        [tempGetCertsResult addObject:[rawResult objectAtIndex:i+1]];
    }
    
    _certComboBoxItems = [[NSArray arrayWithArray:tempGetCertsResult] retain];
    
    [_certComboBox reloadData];
    
    [pool release];
}

- (void)checkCerts:(NSTimer *)timer {
    if ([_certTask isRunning] == 0) {
        [timer invalidate];
        [_certTask release];
        _certTask = nil;
        
        if ([_certComboBoxItems count] > 0) {
            NSLog(@"Get Certs done");
            [_statusLabel setStringValue:_(@"Signing Certificate IDs extracted")];
            
            if ([_defaults valueForKey:kCertIndexKey]) {
                
                NSInteger selectedIndex = [[_defaults valueForKey:kCertIndexKey] integerValue];
                if (selectedIndex != -1) {
                    NSString *selectedItem = [self comboBox:_certComboBox objectValueForItemAtIndex:selectedIndex];
                    [_certComboBox setObjectValue:selectedItem];
                    [_certComboBox selectItemAtIndex:selectedIndex];
                }
                
                [self enableControls];
            }
        } else {
            NSRunAlertPanel(@"Error",
                            _(@"Getting Certificate IDs failed"),
                            @"OK",nil,nil);
            [self enableControls];
            [_statusLabel setStringValue:@"Ready"];
        }
    }
}

#pragma mark - Unzip process

- (void)doUnzip {
    if (_originalIpaPath && [_originalIpaPath length] > 0) {
        NSLog(@"Unzipping %@",_originalIpaPath);
        [_statusLabel setStringValue:_(@"Extracting original app")];
    }
    
    _unzipTask = [[NSTask alloc] init];
    [_unzipTask setLaunchPath:@"/usr/bin/unzip"];
    [_unzipTask setArguments:[NSArray arrayWithObjects:@"-q", _originalIpaPath, @"-d", [self unzippedIPAPath], nil]];
    
    __block id taskComplete;
    taskComplete = [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                                     object:_unzipTask
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification *note) {
                                                                     [[NSNotificationCenter defaultCenter] removeObserver:taskComplete];
                                                                     [self checkUnzip];
                                                                 }];
    [_unzipTask launch];
}

- (void)checkUnzip {
    if ([_unzipTask isRunning] == 0) {
        [_unzipTask release];
        _unzipTask = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"]]) {
            NSLog(@"Unzipping done");
            [_statusLabel setStringValue:_(@"Original app extracted")];
            
            if (_changeBundleIDCheckbox.state == NSOnState) {
                [self doBundleIDChange:_bundleIDField.stringValue];
            }
            
            if ([[_provisioningPathField stringValue] isEqualTo:@""]) {
                [self doChannelTask];
            } else {
                [self doProvisioning];
            }
        } else {
            NSRunAlertPanel(@"Error",
                            _(@"Unzip failed"),
                            @"OK",nil,nil);
            [self enableControls];
            [_statusLabel setStringValue:@"Ready"];
        }
    }
}

#pragma mark - Provisioning process

- (void)doProvisioning {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            _appPath = [[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
            if ([[NSFileManager defaultManager] fileExistsAtPath:[_appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                NSLog(@"Found embedded.mobileprovision, deleting.");
                [[NSFileManager defaultManager] removeItemAtPath:[_appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
            }
            break;
        }
    }
    
    NSString *targetPath = [_appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    
    _provisioningTask = [[NSTask alloc] init];
    [_provisioningTask setLaunchPath:@"/bin/cp"];
    [_provisioningTask setArguments:[NSArray arrayWithObjects:[_provisioningPathField stringValue], targetPath, nil]];
    
    [_provisioningTask launch];
    
    __block id taskComplete;
    taskComplete = [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                                     object:_provisioningTask
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification *note) {
                                                                     [[NSNotificationCenter defaultCenter] removeObserver:self];
                                                                     [self checkProvisioning];
                                                                 }];
}

- (void)checkProvisioning {
    if ([_provisioningTask isRunning] == 0) {
        [_provisioningTask release];
        _provisioningTask = nil;
        
        NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] error:nil];
        
        for (NSString *file in dirContents) {
            if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
                _appPath = [[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
                if ([[NSFileManager defaultManager] fileExistsAtPath:[_appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                    
                    BOOL identifierOK = FALSE;
                    NSString *identifierInProvisioning = @"";
                    
                    NSString *embeddedProvisioning = [NSString stringWithContentsOfFile:[_appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] encoding:NSASCIIStringEncoding error:nil];
                    NSArray* embeddedProvisioningLines = [embeddedProvisioning componentsSeparatedByCharactersInSet:
                                                          [NSCharacterSet newlineCharacterSet]];
                    
                    for (int i = 0; i <= [embeddedProvisioningLines count]; i++) {
                        if ([[embeddedProvisioningLines objectAtIndex:i] rangeOfString:@"application-identifier"].location != NSNotFound) {
                            
                            NSInteger fromPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"<string>"].location + 8;
                            
                            NSInteger toPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"</string>"].location;
                            
                            NSRange range;
                            range.location = fromPosition;
                            range.length = toPosition-fromPosition;
                            
                            NSString *fullIdentifier = [[embeddedProvisioningLines objectAtIndex:i+1] substringWithRange:range];
                            
                            NSArray *identifierComponents = [fullIdentifier componentsSeparatedByString:@"."];
                            
                            if ([[identifierComponents lastObject] isEqualTo:@"*"]) {
                                identifierOK = TRUE;
                            }
                            
                            for (int i = 1; i < [identifierComponents count]; i++) {
                                identifierInProvisioning = [identifierInProvisioning stringByAppendingString:[identifierComponents objectAtIndex:i]];
                                if (i < [identifierComponents count]-1) {
                                    identifierInProvisioning = [identifierInProvisioning stringByAppendingString:@"."];
                                }
                            }
                            break;
                        }
                    }
                    
                    NSLog(@"Mobileprovision identifier: %@",identifierInProvisioning);
                    
                    NSString *infoPlist = [NSString stringWithContentsOfFile:[_appPath stringByAppendingPathComponent:@"Info.plist"] encoding:NSASCIIStringEncoding error:nil];
                    if ([infoPlist rangeOfString:identifierInProvisioning].location != NSNotFound) {
                        NSLog(@"Identifiers match");
                        identifierOK = TRUE;
                    }
                    
                    if (identifierOK) {
                        NSLog(@"Provisioning completed.");
                        [_statusLabel setStringValue:@"Provisioning completed"];
                        [self extractEntitlements];
                    } else {
                        NSRunAlertPanel(@"Error",
                                        @"Product identifiers don't match",
                                        @"OK",nil,nil);
                        [self enableControls];
                        [_statusLabel setStringValue:@"Ready"];
                    }
                } else {
                    NSRunAlertPanel(@"Error",
                                    @"Provisioning failed",
                                    @"OK",nil,nil);
                    [self enableControls];
                    [_statusLabel setStringValue:@"Ready"];
                }
                break;
            }
        }
    }
}

#pragma mark - Entitlements process

- (void)extractEntitlements {
    _appPath = nil;
    
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            _appPath = [[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
            NSLog(@"Found %@",_appPath);
            _appName = [file retain];
            [_statusLabel setStringValue:[NSString stringWithFormat:_(@"Codesigning %@"),file]];
            break;
        }
    }
    
    if (_appPath) {
        NSTask *entitlementTask = [[[NSTask alloc] init] autorelease];
        [entitlementTask setLaunchPath:@"/usr/bin/codesign"];
        [entitlementTask setArguments:@[ @"-d", @"--entitlements", @"-", _appPath ]];
        
        [_appPath retain];
        
        NSPipe *pipe = [NSPipe pipe];
        [entitlementTask setStandardOutput:pipe];
        [entitlementTask setStandardError:pipe];
        NSFileHandle *handle = [pipe fileHandleForReading];
        [entitlementTask launch];
        [self watchEntitlements:handle];
        __block id taskComplete;
        taskComplete = [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                                         object:entitlementTask
                                                                          queue:nil
                                                                     usingBlock:^(NSNotification *note) {
                                                                         [[NSNotificationCenter defaultCenter] removeObserver:taskComplete];
                                                                         [self doChannelTask];
                                                                     }];
    }
}

- (void)watchEntitlements:(NSFileHandle *)streamHandle {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    
    NSString *originalEntitlements = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    NSArray *lines = [originalEntitlements componentsSeparatedByString:@"\n"];
    
    NSString *content = @"";
    
    int beginLine = 0;
    int endLine = 0;
    for (int i = 0; i < lines.count; i++) {
        NSString *line = [lines objectAtIndex:i];
        
        if ([line rangeOfString:@"<!DOCTYPE plist PUBLIC"].location != NSNotFound) {
            beginLine = i;
            continue;
        }
        
        if ([line rangeOfString:@"</plist>"].location != NSNotFound) {
            endLine = i;
            break;
        }
    }
    
    for (int i = beginLine; i <= endLine; i++) {
        NSString *line = [lines objectAtIndex:i];
        content = [content stringByAppendingString:line];
        
        if (i < endLine) {
            content = [content stringByAppendingString:@"\n"];
        }
    }
    
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if ([data writeToFile:[self entitlementsPath] atomically:YES]) {
        NSLog(@"Create entitlements.plist success in: %@", [self entitlementsPath]);
    }
    [pool release];
}

#pragma mark - Change bundle ID process

- (BOOL)doBundleIDChange:(NSString *)newBundleID {
    BOOL success = YES;
    
    success &= [self doAppBundleIDChange:newBundleID];
    success &= [self doITunesMetadataBundleIDChange:newBundleID];
    
    return success;
}

- (BOOL)doITunesMetadataBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self unzippedIPAPath] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"plist"]) {
            infoPlistPath = [[self unzippedIPAPath] stringByAppendingPathComponent:file];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistiTunesArtwork newBundleID:newBundleID plistOutOptions:NSPropertyListXMLFormat_v1_0];
    
}

- (BOOL)doAppBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            infoPlistPath = [[[[self unzippedIPAPath] stringByAppendingPathComponent:kPayloadDirName]
                              stringByAppendingPathComponent:file]
                             stringByAppendingPathComponent:kInfoPlistFilename];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistApp newBundleID:newBundleID plistOutOptions:NSPropertyListBinaryFormat_v1_0];
}

- (BOOL)changeBundleIDForFile:(NSString *)filePath bundleIDKey:(NSString *)bundleIDKey newBundleID:(NSString *)newBundleID plistOutOptions:(NSPropertyListWriteOptions)options {
    
    NSMutableDictionary *plist = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        plist = [[[NSMutableDictionary alloc] initWithContentsOfFile:filePath] autorelease];
        [plist setObject:newBundleID forKey:bundleIDKey];
        
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:plist format:options options:kCFPropertyListImmutable error:nil];
        
        return [xmlData writeToFile:filePath atomically:YES];
        
    }
    
    return NO;
}

#pragma mark - Channel process

- (void)doChannelTask {
    if (_channelArray) {
        [_channelArray release];
        
        _channelArray = nil;
    }
    _channelArray = [[self parseChannelFile:_channelPathField.stringValue] retain];
    _currentZipTaskIndex = 0;
    
    if (_channelArray.count > 0) {
        NSDictionary *channelDict = [_channelArray objectAtIndex:0];
        [self createChannelFile:channelDict];
    } else {
        [self doCodeSigning];
    }
}

- (void)createChannelFile:(NSDictionary *)channelDict {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self channelPath]]) {
        [[NSFileManager defaultManager] removeItemAtPath:[self channelPath] error:nil];
    }
    NSString *channelNumber = [channelDict objectForKey:kChannelNumberKey];
    NSData *channelData = [channelNumber dataUsingEncoding:NSASCIIStringEncoding];
    
    if ([channelData writeToFile:[self channelPath] atomically:YES]) {
        [self doCodeSigning];
    } else {
        NSRunAlertPanel(@"Error",
                        @"Create channel failed",
                        @"OK",nil,nil);
        [self enableControls];
        [_statusLabel setStringValue:@"Ready"];
    }
}

#pragma mark - Codesigning process

- (void)doCodeSigning {
    if (_appPath) {
        NSString *resourceRulesPath = [[NSBundle mainBundle] pathForResource:@"ResourceRules" ofType:@"plist"];
        NSString *resourceRulesArgument = [NSString stringWithFormat:@"--resource-rules=%@",resourceRulesPath];
        
        NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", [_certComboBox objectValue], resourceRulesArgument, nil];
        
        if (![[_entitlementField stringValue] isEqualToString:@""]) {
            [arguments addObject:[NSString stringWithFormat:@"--entitlements=%@", [_entitlementField stringValue]]];
        } else {
            // Check if original entitlements exist
            if ([[NSFileManager defaultManager] fileExistsAtPath:[self entitlementsPath]]) {
                [arguments addObject:[NSString stringWithFormat:@"--entitlements=%@", [self entitlementsPath]]];
            }
        }
        [arguments addObjectsFromArray:[NSArray arrayWithObjects:_appPath, nil]];
        
        _codesignTask = [[NSTask alloc] init];
        [_codesignTask setLaunchPath:@"/usr/bin/codesign"];
        [_codesignTask setArguments:arguments];
        
        NSPipe *pipe=[NSPipe pipe];
        [_codesignTask setStandardOutput:pipe];
        [_codesignTask setStandardError:pipe];
        NSFileHandle *handle=[pipe fileHandleForReading];
        
        [_codesignTask launch];
        
        [self watchCodesigning:handle];
        __block id taskComplete;
        taskComplete = [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                                         object:_codesignTask
                                                                          queue:nil
                                                                     usingBlock:^(NSNotification *note) {
                                                                         [[NSNotificationCenter defaultCenter] removeObserver:taskComplete];
                                                                         [self checkCodesigning];
                                                                     }];
    }
}

- (void)watchCodesigning:(NSFileHandle*)streamHandle {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    
    _codesigningResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    
    [pool release];
}

- (void)checkCodesigning {
    if ([_codesignTask isRunning] == 0) {
        [_codesignTask release];
        _codesignTask = nil;
        NSLog(@"Codesigning done");
        [_statusLabel setStringValue:@"Codesigning completed"];
        [self doVerifySignature];
    }
}

#pragma mark - Verification process

- (void)doVerifySignature {
    if (_appPath) {
        _verifyTask = [[NSTask alloc] init];
        [_verifyTask setLaunchPath:@"/usr/bin/codesign"];
        [_verifyTask setArguments:[NSArray arrayWithObjects:@"-v", _appPath, nil]];
        
        NSLog(@"Verifying %@",_appPath);
        [_statusLabel setStringValue:[NSString stringWithFormat:_(@"Verifying %@"),_appName]];
        
        NSPipe *pipe=[NSPipe pipe];
        [_verifyTask setStandardOutput:pipe];
        [_verifyTask setStandardError:pipe];
        NSFileHandle *handle=[pipe fileHandleForReading];
        
        [_verifyTask launch];
        
        [self watchVerificationProcess:handle];
        __block id taskComplete;
        taskComplete = [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                                         object:_verifyTask
                                                                          queue:nil
                                                                     usingBlock:^(NSNotification *note) {
                                                                         [[NSNotificationCenter defaultCenter] removeObserver:taskComplete];
                                                                         [self checkVerificationProcess];
                                                                     }];
    }
}

- (void)watchVerificationProcess:(NSFileHandle*)streamHandle {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    
    _verificationResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    
    [pool release];
}

- (void)checkVerificationProcess {
    if ([_verifyTask isRunning] == 0) {
        [_verifyTask release];
        _verifyTask = nil;
        if ([_verificationResult length] == 0) {
            NSLog(@"Verification done");
            [_statusLabel setStringValue:@"Verification completed"];
            [self doZip];
        } else {
            NSString *error = [[_codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:_verificationResult];
            NSRunAlertPanel(@"Signing failed", error, @"OK",nil, nil);
            [self enableControls];
            [_statusLabel setStringValue:_(@"Please try again")];
        }
    }
}

#pragma mark - Zip process

- (void)doZip {
    if (_appPath) {
        NSArray *destinationPathComponents = [_originalIpaPath pathComponents];
        NSString *destinationPath = @"";
        
        for (int i = 0; i < ([destinationPathComponents count]-1); i++) {
            destinationPath = [destinationPath stringByAppendingPathComponent:[destinationPathComponents objectAtIndex:i]];
        }
        destinationPath = [destinationPath stringByAppendingPathComponent:kTHPackagingOutput];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:destinationPath
                                      withIntermediateDirectories:NO
                                                       attributes:nil
                                                            error:nil];
        }
        destinationPath = [destinationPath stringByAppendingPathComponent:[self zippedNameForZipTaskIndex:_currentZipTaskIndex]];
        
        NSLog(@"Dest: %@",destinationPath);
        
        _zipTask = [[NSTask alloc] init];
        [_zipTask setLaunchPath:@"/usr/bin/zip"];
        [_zipTask setCurrentDirectoryPath:[self unzippedIPAPath]];
        [_zipTask setArguments:[NSArray arrayWithObjects:@"-qry", destinationPath, @".", nil]];
        
        NSLog(@"Zipping %@", destinationPath);
        [_statusLabel setStringValue:[NSString stringWithFormat:_(@"Saving %@"),[self zippedNameForZipTaskIndex:_currentZipTaskIndex]]];
        
        [_zipTask launch];
        
        __block id taskComplete;
        taskComplete = [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                                         object:_zipTask
                                                                          queue:nil
                                                                     usingBlock:^(NSNotification *note) {
                                                                         [[NSNotificationCenter defaultCenter] removeObserver:taskComplete];
                                                                         [self checkZip];
                                                                     }];
    }
}

- (NSString *)zippedNameForZipTaskIndex:(NSInteger)taskIndex {
    NSString *zippedName = @"";
    if (_channelArray.count > taskIndex) {
        NSDictionary *channelDict = [_channelArray objectAtIndex:taskIndex];
        zippedName = [channelDict objectForKey:kChannelNameKey];
        zippedName = [zippedName stringByAppendingPathExtension:@"ipa"];
    } else {
        zippedName = [_originalIpaPath lastPathComponent];
        zippedName = [zippedName substringToIndex:[zippedName length]-4];
        zippedName = [zippedName stringByAppendingString:@"-packaged"];
        zippedName = [zippedName stringByAppendingPathExtension:@"ipa"];
    }
    return zippedName;
}

- (void)checkZip {
    if ([_zipTask isRunning] == 0) {
        [_zipTask release];
        _zipTask = nil;
        NSLog(@"Zipping done");
        [_statusLabel setStringValue:[NSString stringWithFormat:_(@"Saved %@"),[self zippedNameForZipTaskIndex:_currentZipTaskIndex]]];
        
        // Check if all zip task done
        if (_channelArray.count > 0) {
            if (_currentZipTaskIndex < _channelArray.count - 1) {
                // Do next zip task
                _currentZipTaskIndex++;
                NSDictionary *channelDict = [_channelArray objectAtIndex:_currentZipTaskIndex];
                [self createChannelFile:channelDict];
                return;
            }
        }
        [[NSFileManager defaultManager] removeItemAtPath:_workingPath error:nil];
        [_appPath release];
        [_workingPath release];
        _outputPath = [[[_originalIpaPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:kTHPackagingOutput] copy];
        [self enableControls];
        
        
        NSString *result = [[_codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:_verificationResult];
        NSLog(@"Codesigning result: %@",result);
    }
}

#pragma mark - UI control

- (void)disableControls {
    [_pathField setEnabled:FALSE];
    [_entitlementField setEnabled:FALSE];
    [_browseButton setEnabled:FALSE];
    [_entitlementBrowseButton setEnabled:FALSE];
    [_channelBrowseButton setEnabled:FALSE];
    [_packagingButton setEnabled:FALSE];
    [_provisioningBrowseButton setEnabled:NO];
    [_provisioningPathField setEnabled:NO];
    [_channelPathField setEnabled:NO];
    [_changeBundleIDCheckbox setEnabled:NO];
    [_bundleIDField setEnabled:NO];
    [_certComboBox setEnabled:NO];
    
    [_flurry startAnimation:self];
    [_flurry setAlphaValue:1.0];
    [_openOutputButton setEnabled:NO];
    
}

- (void)enableControls {
    [_pathField setEnabled:TRUE];
    [_entitlementField setEnabled:TRUE];
    [_browseButton setEnabled:TRUE];
    [_channelBrowseButton setEnabled:TRUE];
    [_packagingButton setEnabled:TRUE];
    [_entitlementBrowseButton setEnabled:TRUE];
    [_provisioningBrowseButton setEnabled:YES];
    [_provisioningPathField setEnabled:YES];
    [_channelPathField setEnabled:YES];
    [_changeBundleIDCheckbox setEnabled:YES];
    [_bundleIDField setEnabled:_changeBundleIDCheckbox.state == NSOnState];
    [_certComboBox setEnabled:YES];
    
    [_flurry stopAnimation:self];
    [_flurry setAlphaValue:0.5];
    
    if (_outputPath.length > 0) {
        [_openOutputButton setEnabled:YES];
    } else {
        [_openOutputButton setEnabled:NO];
    }
}

#pragma mark - NSComboBoxDataSource

-(NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox {
    NSInteger count = 0;
    if ([aComboBox isEqual:_certComboBox]) {
        count = [_certComboBoxItems count];
    } 
    return count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    id item = nil;
    if ([aComboBox isEqual:_certComboBox]) {
        item = [_certComboBoxItems objectAtIndex:index];
    }
    return item;
}

#pragma mark - Help methods

- (NSString *)channelPath {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *channelPath = @"";
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            channelPath = [NSString stringWithFormat:@"%@/%@/%@/%@", [self unzippedIPAPath], kPayloadDirName, file, kChannelFileName];
            break;
        }
    }
    return channelPath;
}

- (NSString *)appPath {
    NSString *theAppPath = @"";;
    
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            theAppPath = [[[self unzippedIPAPath] stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
            break;
        }
    }
    return theAppPath;
}

- (NSString *)unzippedIPAPath {
    return [_workingPath stringByAppendingPathComponent:kUnzippedIPAPath];
}

- (NSString *)entitlementsPath {
    return [_workingPath stringByAppendingString:@"/entitlements.plist"];
}

- (NSArray *)parseChannelFile:(NSString *)filePath {
    NSMutableArray *channelArray = [NSMutableArray array];
    NSData *channelData = [NSData dataWithContentsOfFile:filePath];
    NSString *channels = [[NSString alloc] initWithData:channelData encoding:NSUTF8StringEncoding];
    NSArray *pairs = [channels componentsSeparatedByString:@"\n"];
    
    for (NSString *pair in pairs) {
        NSArray *keyValue = [pair componentsSeparatedByString:@":"];
        
        if (keyValue.count == 2) {
            NSString *key = [keyValue objectAtIndex:0];
            NSString *value = [keyValue objectAtIndex:1];
            
            if (key && value) {
                NSDictionary *tempDict = @{
                    kChannelNameKey : [keyValue objectAtIndex:0],
                    kChannelNumberKey : [keyValue objectAtIndex:1]
                };
                [channelArray addObject:tempDict];
            }
        }
    }
    return [NSArray arrayWithArray:channelArray];
}

@end
