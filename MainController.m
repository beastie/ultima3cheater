#import "MainController.h"

BOOL IsTigerOrLater(void);

@implementation MainController

+ (void) recursiveSetMinMaxFormattersForView:(NSView *)theView
{
	if ([theView isKindOfClass:[NSTextField class]] &&
		[(NSTextField *)theView isEditable])
		{
		NSTextField *textField = (NSTextField *)theView;
		static NSMutableDictionary *sFormatters = nil;
		if (!sFormatters)
			sFormatters = [[NSMutableDictionary alloc] init];
		if ([textField tag])
			{
			NSString *maxString = [NSString stringWithFormat:@"%d", [textField tag]];
			NSNumberFormatter *theFormatter = [sFormatters objectForKey:maxString];
			if (!theFormatter)
				{
				theFormatter = [[[NSNumberFormatter alloc] init] autorelease];
				[sFormatters setObject:theFormatter forKey:maxString];
				[theFormatter setFormat:@"#"];
				if (IsTigerOrLater())
					{
					[theFormatter setMinimum:[NSNumber numberWithInt:0]];
					[theFormatter setMaximum:[NSNumber numberWithInt:[textField tag]]];
					}
				else
					{
					[theFormatter setMinimum:[NSDecimalNumber decimalNumberWithString:@"0"]];
					[theFormatter setMaximum:[NSDecimalNumber decimalNumberWithString:maxString]];
					}
				}
			[textField setFormatter:theFormatter];
			}
		}
	else
		{
		NSArray *subs = [theView subviews];
		int i; for (i=[subs count]-1; i>=0; i--)
			[MainController recursiveSetMinMaxFormattersForView:[subs objectAtIndex:i]];
		}
}

- (void) displayCharacterWindowForIndex:(int)charIndex
{
	NSWindow *theWindow = [mCharacterWindows objectAtIndex:charIndex];
	if (![theWindow isKindOfClass:[NSWindow class]])
		{
		NSMutableDictionary *charDictionary = [[mRoster objectForKey:@"roster"] objectAtIndex:charIndex];
		NSNib *theNib = [[NSNib alloc] initWithNibNamed:@"Character" bundle:[NSBundle mainBundle]];
		if (theNib)
			{
			NSArray *theObjects = nil;
			if ([theNib instantiateNibWithOwner:charDictionary topLevelObjects:&theObjects])
				{
				theWindow = [theObjects objectAtIndex:0];
				[mCharacterWindows replaceObjectAtIndex:charIndex withObject:theWindow];
				[MainController recursiveSetMinMaxFormattersForView:[theWindow contentView]];
				static NSPoint sCharWindowPosn = { 0.0, 0.0 };
				if (sCharWindowPosn.y != 0.0)
					{ // just offset from the last position we chose.
					sCharWindowPosn.x += 23;
					sCharWindowPosn.y -= 23;
					}
				else
					{ // find a good position for the first character window.
					NSRect rosterFrame = [mainWindow frame];
					NSArray *screens = [NSScreen screens];
					NSScreen *theScreen = nil;
					// figure out which screen the roster frame is on
					int i = [screens count]-1;
					while (!theScreen && i>=0)
						{
						NSScreen *aScreen = [screens objectAtIndex:i--];
						if (NSPointInRect(rosterFrame.origin, [aScreen frame]))
							theScreen = aScreen;
						}
					if (!theScreen && [screens count])
						theScreen = [screens objectAtIndex:0];
					// see if we can put the character window to the right of the roster
					sCharWindowPosn = NSMakePoint(NSMaxX(rosterFrame)+8, NSMaxY(rosterFrame) - [theWindow frame].size.height);
					// if not, put it on the left side of the screen.
					if (theScreen && !NSPointInRect(NSMakePoint(sCharWindowPosn.x + [theWindow frame].size.width, sCharWindowPosn.y), [theScreen frame]))
						sCharWindowPosn.x = [theScreen frame].origin.x + 8;
					}
				[theWindow setFrameOrigin:sCharWindowPosn];
				}
			else
				{ NSLog(@"Character failed nib instantiation %@", theNib); NSBeep(); }
			}
		}
	[theWindow makeKeyAndOrderFront:self];
}

- (void) openRosterEntry:(id)sender
{
	int clickedRoster = [sender selectedColumn] * 10 + [sender selectedRow];
	if (clickedRoster>=0)
		{
		NSString *aName = [[[mRoster objectForKey:@"roster"] objectAtIndex:clickedRoster] objectForKey:@"name"];
		if (!aName)
			[[NSSound soundNamed:@"Basso"] play];
		else
			[self displayCharacterWindowForIndex:clickedRoster];
		}
}

- (void) updateRosterButtons
{
	NSArray *roster = [mRoster objectForKey:@"roster"];
	if ([roster count]==20)
		{
		unsigned char *party = (unsigned char *)[[mRoster objectForKey:@"PRTY"] bytes];
		
		int i; for (i=0; i<20; i++)
			{
			NSButtonCell *cell = [rosterMatrix cellAtRow:i%10 column:(i>9)];
			NSString *aName = [[roster objectAtIndex:i] objectForKey:@"name"];
			[[roster objectAtIndex:i] addObserver:self forKeyPath:@"name" 
                 options:0 context:cell];
			BOOL isPartyMember = NO;
			if ([aName length])
				{
				isPartyMember =
					(party[6]==(i+1) || party[7]==(i+1) || party[8]==(i+1) || party[9]==(i+1));
					
				[cell setTitle:aName];
				}
			else
				[cell setTitle:@"--"];
			[cell setBezelStyle:(isPartyMember) ?
				NSTexturedSquareBezelStyle :
				NSShadowlessSquareBezelStyle];
			[cell setBordered:([aName length]>0)];
			}
		}
}

// 0 = no err
// 1 = can't find prefs folder
// 2 = can't find roster
// 3 = can't open roster (probably busy)
- (int) getRoster
{
	short prefVRefNum;
	long prefDirID;
	OSErr error = FindFolder(kOnSystemDisk, kPreferencesFolderType, kDontCreateFolder,
		&prefVRefNum, &prefDirID);
	if (error != noErr)
		{ NSLog(@"FindFolder prefs returned %d", error); return 1; }

	Str255 fileName = "\pcom.lairware.ultima3.roster";
	FSSpec fss;
	error = FSMakeFSSpec(prefVRefNum, prefDirID, fileName, &fss);
	if (error != noErr)
		{ NSLog(@"FSMakeFSSpec prefs returned %d", error); return 2; }

	int rosterRefNum = FSpOpenResFile(&fss, fsRdWrPerm);  
	if (rosterRefNum == -1)
		{ NSLog(@"FSpOpenResFile prefs failed"); return 3; }
	
	[mRoster release];
	mRoster = [[NSMutableDictionary alloc] init];
	
	Handle partyHandle = GetResource('PRTY', 400);
	LoadResource(partyHandle);
	long partyDataSize = GetHandleSize(partyHandle);
	if (partyDataSize)
		[mRoster setObject:[NSData dataWithBytes:*partyHandle length:partyDataSize] forKey:@"PRTY"];
	ReleaseResource(partyHandle);	

	Handle rosterHandle = GetResource('ROST', 400);
	LoadResource(rosterHandle);
	long rosterDataSize = GetHandleSize(rosterHandle);
	if (rosterDataSize)
		{
		[mRoster setObject:[NSMutableData dataWithBytes:*rosterHandle length:rosterDataSize] forKey:@"ROST"];
	
		NSMutableArray *roster = [NSMutableArray array];
		[mRoster setObject:roster forKey:@"roster"];
		int player;
		for (player=0; player<20; player++) {
			NSMutableDictionary *thisChar = [NSMutableDictionary dictionary];
			[roster addObject:thisChar];
			unsigned char *raw = (unsigned char*)(*rosterHandle + player*64);
			if (raw[0])
				{
				// name
				NSData *nameData = [NSData dataWithBytes:raw length:strlen(raw)];
				[thisChar setObject:[[[NSString alloc] initWithData:nameData encoding:NSMacOSRomanStringEncoding] autorelease] forKey:@"name"]; 
				// cards & marks
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x08)] forKey:@"cardDeath"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x02)] forKey:@"cardSol"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x01)] forKey:@"cardLove"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x04)] forKey:@"cardMoons"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x10)] forKey:@"markForce"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x20)] forKey:@"markFire"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x40)] forKey:@"markSnake"];
				[thisChar setObject:[NSNumber numberWithBool:(raw[14] & 0x80)] forKey:@"markKings"];

				[thisChar setObject:[NSNumber numberWithInt:raw[16]] forKey:@"inOut"];
				// misc equipment
				[thisChar setObject:[NSNumber numberWithInt:raw[15]] forKey:@"torches"];
				[thisChar setObject:[NSNumber numberWithInt:raw[37]] forKey:@"gems"];
				[thisChar setObject:[NSNumber numberWithInt:raw[38]] forKey:@"keys"];
				[thisChar setObject:[NSNumber numberWithInt:raw[39]] forKey:@"powders"];
				// health
				int healthIndex = -1;
				switch (raw[17]) {
					case 'G': healthIndex=0; break;
					case 'P': healthIndex=1; break;
					case 'D': healthIndex=2; break;
					case 'A': healthIndex=3; }
				[thisChar setObject:[NSNumber numberWithInt:healthIndex] forKey:@"health"];
				// attributes
				[thisChar setObject:[NSNumber numberWithInt:raw[18]] forKey:@"strength"];
				[thisChar setObject:[NSNumber numberWithInt:raw[19]] forKey:@"dexterity"];
				[thisChar setObject:[NSNumber numberWithInt:raw[20]] forKey:@"intelligence"];
				[thisChar setObject:[NSNumber numberWithInt:raw[21]] forKey:@"wisdom"];
				// race
				int raceIndex = -1;
				switch (raw[22]) {
					case 'H': raceIndex=0; break;
					case 'E': raceIndex=1; break;
					case 'D': raceIndex=2; break;
					case 'B': raceIndex=3; break;
					case 'F': raceIndex=4; }
				[thisChar setObject:[NSNumber numberWithInt:raceIndex] forKey:@"race"];
				// class
				int classIndex = -1;
				switch (raw[23]) {
					case 'F': classIndex=0; break;
					case 'C': classIndex=1; break;
					case 'W': classIndex=2; break;
					case 'T': classIndex=3; break;
					case 'P': classIndex=4; break;
					case 'B': classIndex=5; break;
					case 'L': classIndex=6; break;
					case 'I': classIndex=7; break;
					case 'D': classIndex=8; break;
					case 'A': classIndex=9; break;
					case 'R': classIndex=10; }
				[thisChar setObject:[NSNumber numberWithInt:classIndex] forKey:@"class"];
				// sex
				int sexIndex = -1;
				switch (raw[24]) {
					case 'M': sexIndex=0; break;
					case 'F': sexIndex=1; break;
					case 'O': sexIndex=2; }
				[thisChar setObject:[NSNumber numberWithInt:sexIndex] forKey:@"sex"];
				
				[thisChar setObject:[NSNumber numberWithInt:raw[25]] forKey:@"mana"];
				int hp = raw[26]*256 + raw[27];
				[thisChar setObject:[NSNumber numberWithInt:hp] forKey:@"hp"];
				int maxhp = raw[28]*256 + raw[29];
				[thisChar setObject:[NSNumber numberWithInt:maxhp] forKey:@"maxhp"];
				int exp = raw[30]*100 + raw[31];
				[thisChar setObject:[NSNumber numberWithInt:exp] forKey:@"experience"];
				int food = raw[32]*100 + raw[33];
				[thisChar setObject:[NSNumber numberWithInt:food] forKey:@"food"];
				int gold = raw[35]*256 + raw[36];
				[thisChar setObject:[NSNumber numberWithInt:gold] forKey:@"gold"];
				
				int i;
				// armour
				[thisChar setObject:[NSNumber numberWithInt:raw[40]] forKey:@"armour"];
				for (i=0; i<7; i++)
					[thisChar setObject:[NSNumber numberWithInt:raw[41+i]] forKey:
						[NSString stringWithFormat:@"armour_%d", i]];
				// weapon
				[thisChar setObject:[NSNumber numberWithInt:raw[48]] forKey:@"weapon"];
				for (i=0; i<15; i++)
					[thisChar setObject:[NSNumber numberWithInt:raw[49+i]] forKey:
						[NSString stringWithFormat:@"weapon_%d", i]];
				}
			}
		}
	ReleaseResource(rosterHandle);	

	CloseResFile(rosterRefNum);
	
	return 0;
}

// 0 = no err
// 1 = can't find prefs folder
// 2 = can't find roster
// 3 = can't open roster (probably busy)
- (int) putRoster
{
	short prefVRefNum;
	long prefDirID;
	OSErr error = FindFolder(kOnSystemDisk, kPreferencesFolderType, kDontCreateFolder,
		&prefVRefNum, &prefDirID);
	if (error != noErr)
		{ NSLog(@"FindFolder prefs put returned %d", error); return 1; }

	Str255 fileName = "\pcom.lairware.ultima3.roster";
	FSSpec fss;
	error = FSMakeFSSpec(prefVRefNum, prefDirID, fileName, &fss);
	if (error != noErr)
		{ NSLog(@"FSMakeFSSpec prefs put returned %d", error); return 2; }

	int rosterRefNum = FSpOpenResFile(&fss, fsRdWrPerm);  
	if (rosterRefNum == -1)
		{ NSLog(@"FSpOpenResFile prefs put failed"); return 3; }

	NSMutableData *ROST = [NSMutableData dataWithCapacity:64 * 20];
	NSArray *roster = [mRoster objectForKey:@"roster"];
	int player; for (player=0; player<[roster count]; player++)
		{
		int i;
		unsigned char byte=0;
		UInt16 twoByte = 0;
		NSDictionary *thisChar = [roster objectAtIndex:player];
		// name
		NSString *name = [thisChar objectForKey:@"name"];
		if ([name length]<1)
			{
			// a completely empty character record.
			[ROST appendData:[NSMutableData dataWithLength:64]];
			}
		else
			{
			NSData *nameData = [name dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
			int length = ([nameData length]<14) ? [nameData length] : 13;
			[ROST appendBytes:[nameData bytes] length:length];
			if (length<13)
				[ROST appendData:[NSMutableData dataWithLength:13-length]];
			// ?
			[ROST appendData:[NSMutableData dataWithLength:1]];
			// cards & marks
			if ([[thisChar objectForKey:@"cardDeath"] boolValue])	byte |= 0x08;
			if ([[thisChar objectForKey:@"cardSol"] boolValue])		byte |= 0x02;
			if ([[thisChar objectForKey:@"cardLove"] boolValue])	byte |= 0x01;
			if ([[thisChar objectForKey:@"cardMoons"] boolValue])	byte |= 0x04;
			if ([[thisChar objectForKey:@"markForce"] boolValue])	byte |= 0x10;
			if ([[thisChar objectForKey:@"markFire"] boolValue])	byte |= 0x20;
			if ([[thisChar objectForKey:@"markSnake"] boolValue])	byte |= 0x40;
			if ([[thisChar objectForKey:@"markKings"] boolValue])	byte |= 0x80;
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			
			byte = [[thisChar objectForKey:@"torches"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];		
			byte = [[thisChar objectForKey:@"inOut"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = (unsigned char)[@"GPDA" characterAtIndex:[[thisChar objectForKey:@"health"] intValue]];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"strength"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"dexterity"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"intelligence"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"wisdom"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = (unsigned char)[@"HEDBF" characterAtIndex:[[thisChar objectForKey:@"race"] intValue]];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = (unsigned char)[@"FCWTPBLIDAR" characterAtIndex:[[thisChar objectForKey:@"class"] intValue]];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = (unsigned char)[@"MFO" characterAtIndex:[[thisChar objectForKey:@"sex"] intValue]];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"mana"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			twoByte = EndianU16_NtoB([[thisChar objectForKey:@"hp"] intValue]);
			[ROST appendData:[NSData dataWithBytes:&twoByte length:2]];
			twoByte = EndianU16_NtoB([[thisChar objectForKey:@"maxhp"] intValue]);
			[ROST appendData:[NSData dataWithBytes:&twoByte length:2]];

			byte = [[thisChar objectForKey:@"experience"] intValue]/100;
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"experience"] intValue] - (byte*100);
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];

			byte = [[thisChar objectForKey:@"food"] intValue]/100;
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			byte = [[thisChar objectForKey:@"food"] intValue] - (byte*100);
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			[ROST appendData:[NSMutableData dataWithLength:1]]; // food fraction
			
			twoByte = EndianU16_NtoB([[thisChar objectForKey:@"gold"] intValue]);
			[ROST appendData:[NSData dataWithBytes:&twoByte length:2]];
			byte = [[thisChar objectForKey:@"gems"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];		
			byte = [[thisChar objectForKey:@"keys"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];		
			byte = [[thisChar objectForKey:@"powders"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];		
			byte = [[thisChar objectForKey:@"armour"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			for (i=0; i<7; i++)
				{ NSString *key = [NSString stringWithFormat:@"armour_%d", i];
				byte = [[thisChar objectForKey:key] intValue];
				[ROST appendData:[NSData dataWithBytes:&byte length:1]]; }
			byte = [[thisChar objectForKey:@"weapon"] intValue];
			[ROST appendData:[NSData dataWithBytes:&byte length:1]];
			for (i=0; i<15; i++)
				{ NSString *key = [NSString stringWithFormat:@"weapon_%d", i];
				byte = [[thisChar objectForKey:key] intValue];
				[ROST appendData:[NSData dataWithBytes:&byte length:1]]; }
			}
		}
	Handle rosterHandle = GetResource('ROST', 400);
	LoadResource(rosterHandle);
	memcpy(*rosterHandle, [ROST bytes], [ROST length]);
	ChangedResource(rosterHandle);
	WriteResource(rosterHandle);
	ReleaseResource(rosterHandle);	

	CloseResFile(rosterRefNum);
	
	return 0;
}

- (BOOL) closeRoster
{
	if (!mRoster)
		return YES;
	
	int result = [self putRoster];
	if (result==0)
		{
		[mRoster release];
		mRoster = nil;
		return YES;
		}
	
	NSString *appTitle = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
	int button = NSRunAlertPanel(appTitle, NSLocalizedString(@"NoWriteRoster", nil), NSLocalizedString(@"Cancel", nil), NSLocalizedString(@"QuitAnyway", nil), nil);
	return (button == NSAlertAlternateReturn);
}

- (void) awakeFromNib
{
	[NSApp setDelegate:self];

	mCharacterWindows = [[NSMutableArray alloc] initWithCapacity:20];
	int i; for (i=0; i<20; i++) { [mCharacterWindows addObject:[NSNull null]]; }
	
	int result = [self getRoster];
	if (result==0)
		[self updateRosterButtons];
	else
		{
		NSString *appTitle = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
		NSString *userName = (NSString *)CSCopyUserName(NO);
		if (userName) [userName autorelease]; else userName = @"this user";

		if (result==2)
			NSRunAlertPanel(appTitle, [NSString stringWithFormat:NSLocalizedString(@"RosterMissing", nil), userName], NSLocalizedString(@"Quit", nil), nil, nil);
		else
			NSRunAlertPanel(appTitle, NSLocalizedString(@"RosterOpen", nil), NSLocalizedString(@"Quit", nil), nil, nil);

		ExitToShell();
		}
}

- (BOOL)windowShouldClose:(id)sender
{
	return [self closeRoster];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	[NSApp terminate:self];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if ([self closeRoster])
		return NSTerminateNow;
	return NSTerminateCancel;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	NSString *newName = [object objectForKey:keyPath];
	[(NSButtonCell *)context setTitle:newName];
}

@end

BOOL IsTigerOrLater(void)
{
    static char _isTigerOrLater = -1;
    if (_isTigerOrLater==-1)
        {
        _isTigerOrLater = 0;
        SInt32 macOSVersion;
        if (Gestalt(gestaltSystemVersion, &macOSVersion) == noErr)
            {
            int majorVersion = ((macOSVersion & 0x0000FF00) >> 8) - 6;
            int minorVersion = ((macOSVersion & 0x000000F0) >> 4);
            if (majorVersion>10 || (majorVersion==10 && minorVersion>=4))
                _isTigerOrLater = 1;
            }
        }
    return (_isTigerOrLater==1);
}
