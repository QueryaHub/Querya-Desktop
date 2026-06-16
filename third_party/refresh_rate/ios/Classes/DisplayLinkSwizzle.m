#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// Key for tagging display links that should bypass the override.
static const void *RRBypassKey = &RRBypassKey;
// Key for storing the original (uncapped) frame rate range.
static const void *RROriginalRangeKey = &RROriginalRangeKey;

/// Global override cap. 0 means no override (pass through).
static float _rr_overrideMaxRate = 0;

/// Storage for tracked display links (weak-ish — we check validity).
static NSPointerArray *_rr_trackedLinks = nil;
static NSLock *_rr_lock = nil;

// Store original IMPs — declared early so swizzled functions can reference them.
static IMP _rr_origAddToRunLoop = NULL;
static IMP _rr_origSetRange = NULL;

#pragma mark - Public C interface (called from Swift)

/// Set the max frame rate cap. Pass 0 to disable.
void RRSetOverrideMaxRate(float rate) {
    _rr_overrideMaxRate = rate;
}

float RRGetOverrideMaxRate(void) {
    return _rr_overrideMaxRate;
}

/// Tag a display link so the swizzle bypasses it.
void RRBypassDisplayLink(CADisplayLink *link) {
    objc_setAssociatedObject(link, RRBypassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/// Apply the current override to all tracked display links.
void RRApplyOverrideToTrackedLinks(void) {
    if (!_rr_lock) return;

    [_rr_lock lock];

    // Compact nil refs
    [_rr_trackedLinks compact];

    NSUInteger count = [_rr_trackedLinks count];
    for (NSUInteger i = 0; i < count; i++) {
        CADisplayLink *link = [_rr_trackedLinks pointerAtIndex:i];
        if (!link) continue;

        // Skip bypassed links
        if (objc_getAssociatedObject(link, RRBypassKey)) continue;

        if (@available(iOS 15.0, *)) {
            // Read stored original range
            NSDictionary *stored = objc_getAssociatedObject(link, RROriginalRangeKey);

            float cap = _rr_overrideMaxRate;

            if (cap > 0 && stored) {
                float origMin = [stored[@"min"] floatValue];
                float origMax = [stored[@"max"] floatValue];
                float origPref = [stored[@"preferred"] floatValue];
                CAFrameRateRange capped = CAFrameRateRangeMake(
                    fminf(origMin, cap),
                    fminf(origMax, cap),
                    fminf(origPref, cap)
                );
                // Use original IMP directly to avoid re-triggering our swizzle
                // (which would overwrite the stored original with the capped value)
                SEL sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
                if (_rr_origSetRange) {
                    ((void (*)(id, SEL, CAFrameRateRange))_rr_origSetRange)(link, sel, capped);
                }
            } else if (cap <= 0 && stored) {
                // Restore original
                float origMin = [stored[@"min"] floatValue];
                float origMax = [stored[@"max"] floatValue];
                float origPref = [stored[@"preferred"] floatValue];
                SEL sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
                if (_rr_origSetRange) {
                    ((void (*)(id, SEL, CAFrameRateRange))_rr_origSetRange)(link, sel, CAFrameRateRangeMake(origMin, origMax, origPref));
                }
            }
        }
    }

    [_rr_lock unlock];
}

#pragma mark - Swizzled implementations

/// Swizzled addToRunLoop:forMode: — tracks every display link.
static void rr_addToRunLoop(CADisplayLink *self, SEL _cmd, NSRunLoop *runloop, NSRunLoopMode mode) {
    // Track this link
    [_rr_lock lock];
    if (_rr_trackedLinks) {
        // Check not already tracked
        BOOL found = NO;
        [_rr_trackedLinks compact];
        for (NSUInteger i = 0; i < [_rr_trackedLinks count]; i++) {
            if ([_rr_trackedLinks pointerAtIndex:i] == (__bridge void *)self) {
                found = YES;
                break;
            }
        }
        if (!found) {
            [_rr_trackedLinks addPointer:(__bridge void *)self];
        }
    }
    [_rr_lock unlock];

    // Call original — the IMP was saved during swizzle
    ((void (*)(id, SEL, NSRunLoop *, NSRunLoopMode))_rr_origAddToRunLoop)(self, _cmd, runloop, mode);
}

/// Swizzled setPreferredFrameRateRange: — stores original range and applies cap.
static void rr_setPreferredFrameRateRange(CADisplayLink *self, SEL _cmd, CAFrameRateRange range) {
    // Bypass tagged links
    if (objc_getAssociatedObject(self, RRBypassKey)) {
        ((void (*)(id, SEL, CAFrameRateRange))_rr_origSetRange)(self, _cmd, range);
        return;
    }

    // Store original range
    if (@available(iOS 15.0, *)) {
        NSDictionary *stored = @{
            @"min": @(range.minimum),
            @"max": @(range.maximum),
            @"preferred": @(range.preferred),
        };
        objc_setAssociatedObject(self, RROriginalRangeKey, stored, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Apply cap if active
    float cap = _rr_overrideMaxRate;
    if (cap > 0) {
        if (@available(iOS 15.0, *)) {
            CAFrameRateRange capped = CAFrameRateRangeMake(
                fminf(range.minimum, cap),
                fminf(range.maximum, cap),
                fminf(range.preferred, cap)
            );
            ((void (*)(id, SEL, CAFrameRateRange))_rr_origSetRange)(self, _cmd, capped);
        } else {
            ((void (*)(id, SEL, CAFrameRateRange))_rr_origSetRange)(self, _cmd, range);
        }
    } else {
        ((void (*)(id, SEL, CAFrameRateRange))_rr_origSetRange)(self, _cmd, range);
    }
}

#pragma mark - +load (runs before main, before Flutter engine starts)

@interface RRDisplayLinkSwizzle : NSObject
@end

@implementation RRDisplayLinkSwizzle

+ (void)load {
    _rr_trackedLinks = [NSPointerArray weakObjectsPointerArray];
    _rr_lock = [[NSLock alloc] init];

    Class cls = [CADisplayLink class];

    // Swizzle addToRunLoop:forMode:
    {
        SEL sel = @selector(addToRunLoop:forMode:);
        Method method = class_getInstanceMethod(cls, sel);
        if (method) {
            _rr_origAddToRunLoop = method_getImplementation(method);
            method_setImplementation(method, (IMP)rr_addToRunLoop);
        }
    }

    // Swizzle setPreferredFrameRateRange: (iOS 15+)
    if (@available(iOS 15.0, *)) {
        SEL sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
        Method method = class_getInstanceMethod(cls, sel);
        if (method) {
            _rr_origSetRange = method_getImplementation(method);
            method_setImplementation(method, (IMP)rr_setPreferredFrameRateRange);
        }
    }
}

@end
