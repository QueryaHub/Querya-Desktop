#import <QuartzCore/QuartzCore.h>

/// Set the max frame rate cap for all display links. Pass 0 to disable.
void RRSetOverrideMaxRate(float rate);

/// Get the current override max rate. 0 means no override.
float RRGetOverrideMaxRate(void);

/// Tag a display link so the swizzle bypasses it (for monitoring/boost links).
void RRBypassDisplayLink(CADisplayLink * _Nonnull link);

/// Apply the current override to all tracked (non-bypassed) display links.
/// Call this after changing the override rate.
void RRApplyOverrideToTrackedLinks(void);
