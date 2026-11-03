#ifndef MANGO_PRIVATE_H
#define MANGO_PRIVATE_H

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>

// Accessibility -> CGWindowID (used by yabai, AeroSpace, rift).
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

// SkyLight read-only helpers (reverse engineered by yabai / rift).
int SLSMainConnectionID(void);
/// "SetsCursorInBackground" lets a background app hide the cursor.
CGError SLSSetConnectionProperty(int cid, int targetCid, CFStringRef key, CFTypeRef value);
CGError SLSGetWindowBounds(int cid, uint32_t wid, CGRect *frame);
CGError SLSGetWindowLevel(int cid, uint32_t wid, int *level);
CGError SLSGetWindowAlpha(int cid, uint32_t wid, float *alpha);
CGError SLSWindowIsOrderedIn(int cid, uint32_t wid, uint8_t *ordered);
CGError SLSGetCurrentCursorLocation(int cid, CGPoint *point);
// Finds the window under a point (direction 1 = top-down).
int SLSFindWindowAndOwner(int cid, int zero, int one, int zero_again,
                          CGPoint *screen_point, CGPoint *window_point,
                          uint32_t *wid, int *wcid);

// Focus a window of another process without the app ordering all its windows
// to the front (yabai / Hammerspoon technique).
CGError _SLPSSetFrontProcessWithOptions(const ProcessSerialNumber *psn, uint32_t wid, uint32_t mode);
CGError SLPSPostEventRecordTo(const ProcessSerialNumber *psn, const uint8_t *bytes);

// The window server's window ids, without their descriptions: CGWindowListCreate, which is
// unavailable to Swift (a CFArray of ids packed as pointers); wrapper in private.m.
CFArrayRef mango_WindowListCreate(void) CF_RETURNS_RETAINED;
// The same for the windows on screen, front to back.
CFArrayRef mango_WindowListCreateOnScreen(void) CF_RETURNS_RETAINED;

// Carbon process helper (deprecated, unavailable to Swift directly); wrapper in private.m.
OSStatus mango_GetProcessForPID(pid_t pid, ProcessSerialNumber *psn);

// MultitouchSupport (private) - raw trackpad contacts for gesturebind.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerId;
    int handId;
    MTVector normalized;
    float size;
    int zero1;
    float angle, majorAxis, minorAxis;
    MTVector mm;
    int zero2[2];
    float unk2;
} MTTouch;
typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches, int numTouches, double timestamp, int frame);
CFArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTDeviceStart(MTDeviceRef device, int unused);
void MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsBuiltIn(MTDeviceRef device);
/// The sensor's size, in hundredths of a millimetre.
int MTDeviceGetSensorSurfaceDimensions(MTDeviceRef device, int *width, int *height);

#endif
