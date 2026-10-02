#import <AppKit/AppKit.h>

BOOL MBPresentTouchBar(NSTouchBar * _Nonnull bar, NSString * _Nullable trayIdentifier);
void MBDismissTouchBar(NSTouchBar * _Nonnull bar);
BOOL MBRegisterControlStripItem(NSTouchBarItem * _Nonnull item);
void MBRemoveControlStripItem(NSTouchBarItem * _Nonnull item);

BOOL MBAdjustBrightness(float delta);
float MBGetBrightness(void);
BOOL MBSetBrightness(float value);
