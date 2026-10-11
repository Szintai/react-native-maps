//
//  AIRMapHeatmap.h
//
//  Native heatmap overlay for react-native-maps' plain Apple Maps / MapKit ("AirMaps") provider.
//  react-native-maps only ships a heatmap implementation for the Google Maps provider
//  (AIRGoogleMapHeatmap, wrapping GMUHeatmapTileLayer from Google-Maps-iOS-Utils) — there is no
//  equivalent for MKMapView, since MapKit has no built-in tile-based heatmap layer. This mirrors
//  the existing AIRMapOverlay pattern (a UIView<MKOverlay> whose renderer rasterizes and draws a
//  CGImage) rather than AIRMapCircle/AIRGoogleMapHeatmap, since AIRMapOverlay is the closest
//  existing "draw an image over a geographic area" precedent in this same library.
//
//  Prop names/types intentionally match AIRGoogleMapHeatmapManager exactly (points/radius/opacity/
//  gradient), so the shared JS side (MapHeatmap.js) needs no changes at all.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>

#import <React/RCTComponent.h>

#import "AIRMap.h"

@class AIRMapHeatmapRenderer;

@interface AIRMapHeatmap : UIView <MKOverlay>

@property (nonatomic, weak) AIRMap *map;
@property (nonatomic, strong) AIRMapHeatmapRenderer *renderer;

@property (nonatomic, copy) NSArray<NSDictionary *> *points;
@property (nonatomic, assign) NSUInteger radius;
@property (nonatomic, assign) float opacity;
@property (nonatomic, copy) NSDictionary *gradient;

#pragma mark MKOverlay protocol

@property (nonatomic, readonly) CLLocationCoordinate2D coordinate;
@property (nonatomic, readonly) MKMapRect boundingMapRect;
- (BOOL)intersectsMapRect:(MKMapRect)mapRect;
- (BOOL)canReplaceMapContent;

@end
