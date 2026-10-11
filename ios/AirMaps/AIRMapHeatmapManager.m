#import "AIRMapHeatmapManager.h"
#import "AIRMapHeatmap.h"

#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTConvert+CoreLocation.h>
#import <React/UIView+React.h>

@implementation AIRMapHeatmapManager

RCT_EXPORT_MODULE()

- (UIView *)view
{
    AIRMapHeatmap *heatmap = [AIRMapHeatmap new];
    return heatmap;
}

// Prop names/types intentionally identical to AIRGoogleMapHeatmapManager, matching the shared
// MapHeatmapProps contract on the JS side.
RCT_EXPORT_VIEW_PROPERTY(points, NSArray<NSDictionary *>)
RCT_EXPORT_VIEW_PROPERTY(radius, NSUInteger)
RCT_EXPORT_VIEW_PROPERTY(opacity, float)
RCT_EXPORT_VIEW_PROPERTY(gradient, NSDictionary *)

@end
