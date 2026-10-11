//
//  AIRMapPulseRing.h
//
//  Native pulsing accuracy ring for react-native-maps' plain Apple Maps / MapKit ("AirMaps")
//  provider. See TESTING.md in this directory for the full root-cause writeup; short version:
//
//  <Circle> (AIRMapCircle) is an MKOverlay. Its setRadius: rebuilds the MKCircle + MKCircleRenderer
//  from scratch and does [_map removeOverlay:self] / [_map addOverlay:self] on every single call,
//  because MKCircle's geometry is immutable. That's fine for occasional radius changes, but when a
//  pulsing ring drives that prop every animation frame (~60/s) via Reanimated, iOS ends up doing a
//  full MKMapView overlay teardown+recreate 60x/sec — the render queue can't keep up, frames get
//  dropped/coalesced, and the ring visibly lags, jumps to an oversized radius, and sticks there
//  until a map pan/zoom forces MapKit to flush the backlog. Android's GMSCircle.radius is a cheap
//  native property (no overlay recreation), which is why the exact same JS animation is smooth
//  there.
//
//  This view sidesteps <Circle> entirely. It's an MKAnnotationView (screen-space positioning, same
//  mechanism AIRMapMarker uses) with a single CAShapeLayer circle, pulsed via a native
//  CABasicAnimation on the layer's transform.scale. Once started, the animation runs on the render
//  server with zero JS/UI-thread involvement per frame, so it can't fall behind. JS only touches
//  this view's props when an actual input changes (position, accuracy score, zoom level, color) —
//  never once per animation frame.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>

#import <React/RCTComponent.h>

#import "AIRMap.h"

@interface AIRMapPulseRing : MKAnnotationView <MKAnnotation>

@property (nonatomic, weak) AIRMap *map;

@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, strong) UIColor *ringColor;
@property (nonatomic, assign) CGFloat baseRadius;
@property (nonatomic, assign) CGFloat maxRadius;
@property (nonatomic, assign) NSInteger pulseDurationMs;

#pragma mark MKAnnotation protocol (optional members)

@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *subtitle;

- (MKAnnotationView *)getAnnotationView;

@end
