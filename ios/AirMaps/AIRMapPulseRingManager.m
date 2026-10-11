//
//  AIRMapPulseRingManager.m
//
//  RCTViewManager for AIRMapPulseRing. See AIRMapPulseRing.h for the root-cause writeup.
//

#import "AIRMapPulseRingManager.h"
#import "AIRMapPulseRing.h"

#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTConvert+CoreLocation.h>
#import <React/UIView+React.h>

@implementation AIRMapPulseRingManager

RCT_EXPORT_MODULE()

- (UIView *)view
{
    return [AIRMapPulseRing new];
}

RCT_REMAP_VIEW_PROPERTY(center, coordinate, CLLocationCoordinate2D)
RCT_EXPORT_VIEW_PROPERTY(ringColor, UIColor)
RCT_EXPORT_VIEW_PROPERTY(baseRadius, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(maxRadius, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(pulseDurationMs, NSInteger)

@end
