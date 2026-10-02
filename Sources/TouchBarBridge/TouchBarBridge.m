#import "TouchBarBridge.h"
#import <objc/message.h>
#import <dlfcn.h>

static void *MBDFRSymbol(const char *name) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
    });
    return framework ? dlsym(framework, name) : NULL;
}

static void MBSetCloseBoxVisible(BOOL visible) {
    void (*setVisible)(BOOL) = MBDFRSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (setVisible) setVisible(visible);
}

BOOL MBPresentTouchBar(NSTouchBar *bar, NSString *trayIdentifier) {
    Class cls = NSTouchBar.class;
    SEL fullWidth = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    SEL appRegion = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if ([cls respondsToSelector:fullWidth]) {
        MBSetCloseBoxVisible(NO);
        ((void (*)(id, SEL, NSTouchBar *, long long, NSString *))objc_msgSend)(cls, fullWidth, bar, 1, trayIdentifier);
        return YES;
    }
    if (![cls respondsToSelector:appRegion]) return NO;
    MBSetCloseBoxVisible(NO);
    ((void (*)(id, SEL, NSTouchBar *, NSString *))objc_msgSend)(cls, appRegion, bar, trayIdentifier);
    return YES;
}

static void *MBDisplayServicesSymbol(const char *name) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL);
    });
    return framework ? dlsym(framework, name) : NULL;
}

float MBGetBrightness(void) {
    int (*get)(CGDirectDisplayID, float *) = MBDisplayServicesSymbol("DisplayServicesGetBrightness");
    float value = 0;
    if (!get || get(CGMainDisplayID(), &value) != 0) return -1;
    return value;
}

BOOL MBSetBrightness(float value) {
    int (*set)(CGDirectDisplayID, float) = MBDisplayServicesSymbol("DisplayServicesSetBrightness");
    return set && set(CGMainDisplayID(), fminf(1, fmaxf(0, value))) == 0;
}

BOOL MBAdjustBrightness(float delta) {
    float value = MBGetBrightness();
    return value >= 0 && MBSetBrightness(value + delta);
}

void MBDismissTouchBar(NSTouchBar *bar) {
    Class cls = NSTouchBar.class;
    SEL selector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if ([cls respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSTouchBar *))objc_msgSend)(cls, selector, bar);
    }
    MBSetCloseBoxVisible(YES);
}

BOOL MBRegisterControlStripItem(NSTouchBarItem *item) {
    SEL add = NSSelectorFromString(@"addSystemTrayItem:");
    SEL remove = NSSelectorFromString(@"removeSystemTrayItem:");
    void (*setPresence)(NSString *, BOOL) = MBDFRSymbol("DFRElementSetControlStripPresenceForIdentifier");
    if (!setPresence || ![NSTouchBarItem.class respondsToSelector:add] ||
        ![NSTouchBarItem.class respondsToSelector:remove]) return NO;
    ((void (*)(id, SEL, NSTouchBarItem *))objc_msgSend)(NSTouchBarItem.class, add, item);
    setPresence(item.identifier, YES);
    return YES;
}

void MBRemoveControlStripItem(NSTouchBarItem *item) {
    void (*setPresence)(NSString *, BOOL) = MBDFRSymbol("DFRElementSetControlStripPresenceForIdentifier");
    if (setPresence) setPresence(item.identifier, NO);
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    if ([NSTouchBarItem.class respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSTouchBarItem *))objc_msgSend)(NSTouchBarItem.class, selector, item);
    }
}
