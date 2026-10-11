#import "AIRMapHeatmap.h"
#import "AIRMapHeatmapRenderer.h"
#import <React/RCTConvert.h>
#import <React/RCTConvert+CoreLocation.h>

@implementation AIRMapHeatmap {
    MKMapRect _mapRect;
}

- (void)setPoints:(NSArray<NSDictionary *> *)points
{
    _points = points;
    [self recomputeBoundingRect];
    [self createRendererIfPossible];
    [self update];
}

- (void)setRadius:(NSUInteger)radius
{
    _radius = radius;
    [self recomputeBoundingRect];
    [self update];
}

- (void)setOpacity:(float)opacity
{
    _opacity = opacity;
    [self update];
}

- (void)setGradient:(NSDictionary *)gradient
{
    _gradient = gradient;
    [self update];
}

// The overlay's bounding rect must cover every point plus enough padding for `radius` (in screen
// points, converted to a rough degrees-of-latitude padding here) so MapKit doesn't cull/clip the
// heatmap's edges when a point sits near the edge of the visible map rect.
- (void)recomputeBoundingRect
{
    if (self.points.count == 0) {
        _mapRect = MKMapRectNull;
        return;
    }

    double minX = DBL_MAX, minY = DBL_MAX, maxX = -DBL_MAX, maxY = -DBL_MAX;
    for (NSDictionary *pointDict in self.points) {
        CLLocationCoordinate2D coordinate = [RCTConvert CLLocationCoordinate2D:pointDict];
        MKMapPoint mapPoint = MKMapPointForCoordinate(coordinate);
        minX = MIN(minX, mapPoint.x);
        minY = MIN(minY, mapPoint.y);
        maxX = MAX(maxX, mapPoint.x);
        maxY = MAX(maxY, mapPoint.y);
    }

    // boundingMapRect is static (computed once here, not per-frame), but `radius` is a constant
    // on-screen point size that the renderer converts to map-points by dividing by the *current*
    // zoomScale — the more zoomed OUT the view is, the more map-points that same on-screen radius
    // covers. A fixed padding constant can't keep up with this: a `fitToCoordinates` preview card
    // zooms out proportionally to how large the route itself is, so a longer route needs
    // proportionally *more* absolute padding just to keep the same on-screen blob radius from
    // being clipped by this rect's own edge. E.g. a ~118km route fit into a small card measured
    // zoomScale ~0.00024, where a 20pt radius needs 20/0.00024 ≈ 82000 map-points of padding — far
    // more than any fixed constant (a previous radius*1000 ≈ 20000 only covered about a quarter of
    // that, hard-cropping the edge point's blob into a flat line right at the rect boundary).
    // Scaling padding off the data's own extent tracks this relationship directly instead of
    // guessing a zoomScale floor: for a viewport that fits the whole dataset, zoomScale is roughly
    // (viewport size / data extent), so needed padding (radius / zoomScale) grows proportionally
    // with the data extent. 15% comfortably covers typical fitToCoordinates edgePadding overhead.
    double dataWidth = maxX - minX;
    double dataHeight = maxY - minY;
    double dataExtent = MAX(dataWidth, dataHeight);
    double padding = MAX(5000.0, MAX((double)self.radius * 1000.0, dataExtent * 0.15));
    _mapRect = MKMapRectMake(minX - padding, minY - padding,
                              (maxX - minX) + padding * 2, (maxY - minY) + padding * 2);
}

- (void)createRendererIfPossible
{
    if (self.renderer != nil || MKMapRectIsNull(_mapRect)) {
        return;
    }
    self.renderer = [[AIRMapHeatmapRenderer alloc] initWithOverlay:self];
}

- (void)update
{
    if (self.renderer == nil || self.map == nil) {
        return;
    }
    [self.map removeOverlay:self];
    [self.map addOverlay:self];
}

#pragma mark MKOverlay implementation

- (CLLocationCoordinate2D)coordinate
{
    return MKCoordinateForMapPoint(MKMapPointMake(MKMapRectGetMidX(_mapRect), MKMapRectGetMidY(_mapRect)));
}

- (MKMapRect)boundingMapRect
{
    return _mapRect;
}

- (BOOL)intersectsMapRect:(MKMapRect)mapRect
{
    return MKMapRectIntersectsRect(_mapRect, mapRect);
}

- (BOOL)canReplaceMapContent
{
    return NO;
}

@end
