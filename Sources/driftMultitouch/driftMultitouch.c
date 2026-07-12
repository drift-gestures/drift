#include "driftMultitouch.h"

// This file is the only place that touches MultitouchSupport.framework's private C API. It maps
// private TXMTFinger frames to the stable TXMTContact callback declared in the public header; all
// recognition and suppression decisions live in Swift.

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(int, void *, int, double, int);
typedef CFMutableArrayRef (*MTDeviceCreateListFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTUnregisterContactFrameCallbackFunction)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTDeviceStartFunction)(MTDeviceRef, int);
typedef int (*MTDeviceStopFunction)(MTDeviceRef);

typedef struct {
    float x;
    float y;
} TXMTPoint;

typedef struct {
    TXMTPoint position;
    TXMTPoint velocity;
} TXMTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerId;
    int handId;
    TXMTVector normalized;
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    TXMTVector absolute;
    int zero2;
    int zero3;
    float normalizedDensity;
} TXMTFinger;

static void *frameworkHandle = NULL;
static MTDeviceCreateListFunction mtDeviceCreateList = NULL;
static MTRegisterContactFrameCallbackFunction mtRegisterContactFrameCallback = NULL;
static MTUnregisterContactFrameCallbackFunction mtUnregisterContactFrameCallback = NULL;
static MTDeviceStartFunction mtDeviceStart = NULL;
static MTDeviceStopFunction mtDeviceStop = NULL;
static CFMutableArrayRef devices = NULL;
static MTDeviceRef activeDevice = NULL;
static TXMTTrackpadSnapshotCallback snapshotCallback = NULL;

static bool tracking = false;
static int trackingFingerCount = 0;
static int lastFrame = 0;
static double lastTimestamp = 0.0;
static double lastX = 0.0;
static double lastY = 0.0;
static double startDistance = 0.0;
static double startAngle = 0.0;
static double lastScale = 1.0;
static double lastRotation = 0.0;
static TXMTContact *contactBuffer = NULL;
static int contactBufferCapacity = 0;

typedef struct {
    int identifier;
    int fingerId;
    int handId;
} TXMTContactIdentity;

static TXMTContactIdentity *trackedContacts = NULL;
static int trackedContactCapacity = 0;

static const char *loadMessage = "Not loaded";

static void *lookupSymbol(const char *name) {
    if (frameworkHandle == NULL) {
        return NULL;
    }
    return dlsym(frameworkHandle, name);
}

TXMTStatus TXMTLoad(void) {
    if (frameworkHandle != NULL && mtDeviceCreateList != NULL &&
        mtRegisterContactFrameCallback != NULL && mtDeviceStart != NULL && mtDeviceStop != NULL) {
        TXMTStatus status = { true, "Enhanced multitouch framework loaded" };
        return status;
    }

    frameworkHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (frameworkHandle == NULL) {
        loadMessage = "MultitouchSupport.framework could not be loaded";
        TXMTStatus status = { false, loadMessage };
        return status;
    }

    mtDeviceCreateList = (MTDeviceCreateListFunction)lookupSymbol("MTDeviceCreateList");
    mtRegisterContactFrameCallback = (MTRegisterContactFrameCallbackFunction)lookupSymbol("MTRegisterContactFrameCallback");
    mtUnregisterContactFrameCallback = (MTUnregisterContactFrameCallbackFunction)lookupSymbol("MTUnregisterContactFrameCallback");
    mtDeviceStart = (MTDeviceStartFunction)lookupSymbol("MTDeviceStart");
    mtDeviceStop = (MTDeviceStopFunction)lookupSymbol("MTDeviceStop");

    if (mtDeviceCreateList == NULL || mtRegisterContactFrameCallback == NULL || mtDeviceStart == NULL || mtDeviceStop == NULL) {
        loadMessage = "Required private multitouch symbols were not found";
        dlclose(frameworkHandle);
        frameworkHandle = NULL;
        TXMTStatus status = { false, loadMessage };
        return status;
    }

    loadMessage = "Enhanced multitouch framework loaded";
    TXMTStatus status = { true, loadMessage };
    return status;
}

static double distanceBetween(TXMTFinger first, TXMTFinger second) {
    double dx = second.normalized.position.x - first.normalized.position.x;
    double dy = second.normalized.position.y - first.normalized.position.y;
    return sqrt((dx * dx) + (dy * dy));
}

static double angleBetween(TXMTFinger first, TXMTFinger second) {
    double dx = second.normalized.position.x - first.normalized.position.x;
    double dy = second.normalized.position.y - first.normalized.position.y;
    return atan2(dy, dx);
}

static double normalizedAngleDelta(double current, double start) {
    double delta = current - start;
    while (delta > M_PI) {
        delta -= 2.0 * M_PI;
    }
    while (delta < -M_PI) {
        delta += 2.0 * M_PI;
    }
    return delta;
}

static bool ensureContactCapacity(int count) {
    if (count <= contactBufferCapacity) {
        return true;
    }
    TXMTContact *resized = realloc(contactBuffer, sizeof(TXMTContact) * (size_t)count);
    if (resized == NULL) {
        return false;
    }
    contactBuffer = resized;
    contactBufferCapacity = count;
    return true;
}

static bool ensureTrackedContactCapacity(int count) {
    if (count <= trackedContactCapacity) {
        return true;
    }
    TXMTContactIdentity *resized = realloc(trackedContacts, sizeof(TXMTContactIdentity) * (size_t)count);
    if (resized == NULL) {
        return false;
    }
    trackedContacts = resized;
    trackedContactCapacity = count;
    return true;
}

static TXMTContactIdentity contactIdentity(TXMTFinger finger) {
    return (TXMTContactIdentity) {
        .identifier = finger.identifier,
        .fingerId = finger.fingerId,
        .handId = finger.handId
    };
}

static bool sameContactIdentity(TXMTContactIdentity first, TXMTContactIdentity second) {
    return first.identifier == second.identifier &&
        first.fingerId == second.fingerId &&
        first.handId == second.handId;
}

static bool contactListMatchesTracked(const TXMTFinger *fingers, int count) {
    if (!tracking || count != trackingFingerCount) {
        return false;
    }

    for (int storedIndex = 0; storedIndex < trackingFingerCount; storedIndex++) {
        bool found = false;
        for (int currentIndex = 0; currentIndex < count; currentIndex++) {
            if (sameContactIdentity(trackedContacts[storedIndex], contactIdentity(fingers[currentIndex]))) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

static void storeTrackedContacts(const TXMTFinger *fingers, int count) {
    for (int index = 0; index < count; index++) {
        trackedContacts[index] = contactIdentity(fingers[index]);
    }
}

static void copyContacts(const TXMTFinger *fingers, int count) {
    for (int index = 0; index < count; index++) {
        TXMTFinger finger = fingers[index];
        contactBuffer[index] = (TXMTContact) {
            .identifier = finger.identifier,
            .state = finger.state,
            .fingerId = finger.fingerId,
            .handId = finger.handId,
            .normalizedX = finger.normalized.position.x,
            .normalizedY = finger.normalized.position.y,
            .normalizedVelocityX = finger.normalized.velocity.x,
            .normalizedVelocityY = finger.normalized.velocity.y,
            .absoluteX = finger.absolute.position.x,
            .absoluteY = finger.absolute.position.y,
            .absoluteVelocityX = finger.absolute.velocity.x,
            .absoluteVelocityY = finger.absolute.velocity.y,
            .size = finger.size,
            .angle = finger.angle,
            .majorAxis = finger.majorAxis,
            .minorAxis = finger.minorAxis,
            .density = finger.normalizedDensity
        };
    }
}

static void emitSnapshot(
    TXMTTouchPhase phase,
    const TXMTContact *contacts,
    int contactCount,
    double timestamp,
    int frame,
    double centerX,
    double centerY,
    double scale,
    double rotationRadians
) {
    if (snapshotCallback == NULL) {
        return;
    }
    TXMTTrackpadSnapshot snapshot = {
        .contacts = contacts,
        .contactCount = contactCount,
        .timestamp = timestamp,
        .frame = frame,
        .phase = phase,
        .centerX = centerX,
        .centerY = centerY,
        .scale = scale,
        .rotationRadians = rotationRadians
    };
    snapshotCallback(&snapshot);
}

static void finishContactSequence(double timestamp, int frame) {
    if (!tracking || snapshotCallback == NULL) {
        return;
    }

    emitSnapshot(
        TXMTTouchPhaseEnded,
        NULL,
        0,
        timestamp > 0.0 ? timestamp : lastTimestamp,
        frame > 0 ? frame : lastFrame,
        lastX,
        lastY,
        lastScale,
        lastRotation
    );

    tracking = false;
    trackingFingerCount = 0;
    startDistance = 0.0;
    startAngle = 0.0;
    lastScale = 1.0;
    lastRotation = 0.0;
}

static int contactFrameCallback(int device, void *data, int fingerCount, double timestamp, int frame) {
    (void)device;
    if (snapshotCallback == NULL) {
        return 0;
    }

    if (fingerCount <= 0 || data == NULL) {
        finishContactSequence(timestamp, frame);
        return 0;
    }

    if (!ensureContactCapacity(fingerCount) || !ensureTrackedContactCapacity(fingerCount)) {
        return 0;
    }

    TXMTFinger *fingers = (TXMTFinger *)data;
    // A finger being added, removed, or reassigned is still part of the same physical gesture.
    // Only a frame with no contacts ends the sequence. Treat identity changes as changed frames
    // and reset pair-relative baselines so multi-finger gestures reach Swift as one recording.
    bool contactSetChanged = tracking && !contactListMatchesTracked(fingers, fingerCount);

    copyContacts(fingers, fingerCount);

    double sumX = 0.0;
    double sumY = 0.0;
    for (int index = 0; index < fingerCount; index++) {
        sumX += fingers[index].normalized.position.x;
        sumY += fingers[index].normalized.position.y;
    }

    double centerX = sumX / (double)fingerCount;
    double centerY = sumY / (double)fingerCount;
    double currentDistance = 0.0;
    double currentAngle = 0.0;
    if (fingerCount >= 2) {
        currentDistance = distanceBetween(fingers[0], fingers[1]);
        currentAngle = angleBetween(fingers[0], fingers[1]);
    }

    TXMTTouchPhase phase = tracking ? TXMTTouchPhaseChanged : TXMTTouchPhaseBegan;
    if (!tracking || contactSetChanged || trackingFingerCount != fingerCount) {
        startDistance = currentDistance;
        startAngle = currentAngle;
        lastScale = 1.0;
        lastRotation = 0.0;
    } else if (startDistance > 0.0001 && currentDistance > 0.0001) {
        lastScale = currentDistance / startDistance;
        lastRotation = normalizedAngleDelta(currentAngle, startAngle);
    }

    tracking = true;
    trackingFingerCount = fingerCount;
    storeTrackedContacts(fingers, fingerCount);
    lastTimestamp = timestamp;
    lastFrame = frame;
    lastX = centerX;
    lastY = centerY;

    emitSnapshot(
        phase,
        contactBuffer,
        fingerCount,
        timestamp,
        frame,
        centerX,
        centerY,
        lastScale,
        lastRotation
    );
    return 0;
}

bool TXMTStart(TXMTTrackpadSnapshotCallback callback) {
    TXMTStatus status = TXMTLoad();
    if (!status.available || callback == NULL) {
        return false;
    }

    devices = mtDeviceCreateList();
    if (devices == NULL || CFArrayGetCount(devices) == 0) {
        loadMessage = "No multitouch devices found";
        if (devices != NULL) {
            CFRelease(devices);
            devices = NULL;
        }
        return false;
    }

    activeDevice = (MTDeviceRef)CFArrayGetValueAtIndex(devices, 0);
    if (activeDevice == NULL) {
        loadMessage = "Could not select a multitouch device";
        CFRelease(devices);
        devices = NULL;
        return false;
    }

    snapshotCallback = callback;
    mtRegisterContactFrameCallback(activeDevice, contactFrameCallback);
    mtDeviceStart(activeDevice, 0);
    loadMessage = "Enhanced multitouch callbacks active";
    return true;
}

void TXMTStop(void) {
    if (activeDevice != NULL) {
        if (mtUnregisterContactFrameCallback != NULL) {
            mtUnregisterContactFrameCallback(activeDevice, contactFrameCallback);
        }
        if (mtDeviceStop != NULL) {
            mtDeviceStop(activeDevice);
        }
    }

    snapshotCallback = NULL;
    activeDevice = NULL;
    if (devices != NULL) {
        CFRelease(devices);
        devices = NULL;
    }
    free(contactBuffer);
    contactBuffer = NULL;
    contactBufferCapacity = 0;
    free(trackedContacts);
    trackedContacts = NULL;
    trackedContactCapacity = 0;
    tracking = false;
    trackingFingerCount = 0;
}
