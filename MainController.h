/* MainController */

#import <Cocoa/Cocoa.h>

@interface MainController : NSObject
{
    IBOutlet NSWindow *mainWindow;
    IBOutlet NSMatrix *rosterMatrix;

	NSMutableDictionary *mRoster;
	NSMutableArray *mCharacterWindows;
}
@end
