#import "private.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
OSStatus mango_GetProcessForPID(pid_t pid, ProcessSerialNumber *psn) {
    return GetProcessForPID(pid, psn);
}
#pragma clang diagnostic pop

CFArrayRef mango_WindowListCreate(void) {
    return CGWindowListCreate(kCGWindowListOptionAll, kCGNullWindowID);
}

CFArrayRef mango_WindowListCreateOnScreen(void) {
    return CGWindowListCreate(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
}
