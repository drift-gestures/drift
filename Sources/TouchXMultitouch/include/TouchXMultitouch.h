#ifndef TOUCHX_MULTITOUCH_H
#define TOUCHX_MULTITOUCH_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    TXMTTouchPhaseBegan = 1,
    TXMTTouchPhaseChanged = 2,
    TXMTTouchPhaseEnded = 3
} TXMTTouchPhase;

// Stable, public representation of one private-framework contact. The bridge copies fields out of
// TXMTFinger so Swift never depends on the private struct's memory layout.
typedef struct {
    int identifier;
    int state;
    int fingerId;
    int handId;
    double normalizedX;
    double normalizedY;
    double normalizedVelocityX;
    double normalizedVelocityY;
    double absoluteX;
    double absoluteY;
    double absoluteVelocityX;
    double absoluteVelocityY;
    double size;
    double angle;
    double majorAxis;
    double minorAxis;
    double density;
} TXMTContact;

// C-side reduction of one private TXMTFinger[] frame. The contact pointer is borrowed and valid
// only for the callback; Swift copies the snapshot before returning.
typedef struct {
    const TXMTContact *contacts;
    int contactCount;
    double timestamp;
    int frame;
    TXMTTouchPhase phase;
    double centerX;
    double centerY;
    double scale;
    double rotationRadians;
} TXMTTrackpadSnapshot;

typedef void (*TXMTTrackpadSnapshotCallback)(const TXMTTrackpadSnapshot *snapshot);

typedef struct {
    bool available;
    const char *message;
} TXMTStatus;

// Loading can fail on systems without compatible private framework symbols; callers should fall back.
TXMTStatus TXMTLoad(void);
bool TXMTStart(TXMTTrackpadSnapshotCallback callback);
void TXMTStop(void);

#ifdef __cplusplus
}
#endif

#endif
