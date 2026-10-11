#import "AIRMapHeatmapRenderer.h"
#import "AIRMapHeatmap.h"
#import <React/RCTConvert.h>
#import <React/RCTConvert+CoreLocation.h>

#pragma mark - Gradient lookup table

// Mirrors GMUGradient's semantics (colors + startPoints + colorMapSize), and falls back to the
// same green->red default google-maps-android-utils itself uses, so an unconfigured heatmap looks
// the same on both platforms.
@interface AIRMapHeatmapGradient : NSObject

@property (nonatomic, strong) NSArray<UIColor *> *colorMap;
@property (nonatomic, assign) NSUInteger colorMapSize;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (UIColor *)colorForIntensity:(float)intensity;

@end

@implementation AIRMapHeatmapGradient

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    if (self = [super init]) {
        NSArray<UIColor *> *colors;
        NSArray<NSNumber *> *startPoints;
        NSUInteger colorMapSize = 256;

        if (dictionary[@"colors"] != nil) {
            colors = [RCTConvert UIColorArray:dictionary[@"colors"]];
        }
        if (dictionary[@"startPoints"] != nil) {
            startPoints = [RCTConvert NSNumberArray:dictionary[@"startPoints"]];
        }
        if (dictionary[@"colorMapSize"] != nil) {
            colorMapSize = [RCTConvert NSUInteger:dictionary[@"colorMapSize"]];
        }
        if (colorMapSize == 0) {
            colorMapSize = 256;
        }

        if (colors.count == 0 || colors.count != startPoints.count) {
            // No (or malformed) gradient prop — default to the same green->red ramp
            // google-maps-android-utils ships, so Android/iOS look the same unconfigured.
            colors = @[[UIColor colorWithRed:102.0 / 255.0 green:225.0 / 255.0 blue:0 alpha:1.0],
                       [UIColor colorWithRed:1.0 green:0 blue:0 alpha:1.0]];
            startPoints = @[@0.2, @1.0];
        }

        _colorMapSize = colorMapSize;
        _colorMap = [self buildColorMapWithColors:colors startPoints:startPoints];
    }
    return self;
}

- (NSArray<UIColor *> *)buildColorMapWithColors:(NSArray<UIColor *> *)colors
                                     startPoints:(NSArray<NSNumber *> *)startPoints
{
    NSMutableArray<UIColor *> *map = [NSMutableArray arrayWithCapacity:self.colorMapSize];
    for (NSUInteger i = 0; i < self.colorMapSize; i++) {
        float t = self.colorMapSize > 1 ? (float)i / (float)(self.colorMapSize - 1) : 0;
        [map addObject:[self colorAtT:t colors:colors startPoints:startPoints]];
    }
    return map;
}

- (UIColor *)colorAtT:(float)t colors:(NSArray<UIColor *> *)colors startPoints:(NSArray<NSNumber *> *)startPoints
{
    if (colors.count == 1) {
        return colors.firstObject;
    }
    if (t <= [startPoints.firstObject floatValue]) {
        return colors.firstObject;
    }
    if (t >= [startPoints.lastObject floatValue]) {
        return colors.lastObject;
    }
    for (NSUInteger i = 0; i < colors.count - 1; i++) {
        float p0 = [startPoints[i] floatValue];
        float p1 = [startPoints[i + 1] floatValue];
        if (t >= p0 && t <= p1) {
            float localT = (p1 - p0) > 0 ? (t - p0) / (p1 - p0) : 0;
            return [self mixColor:colors[i] withColor:colors[i + 1] amount:localT];
        }
    }
    return colors.lastObject;
}

- (UIColor *)mixColor:(UIColor *)a withColor:(UIColor *)b amount:(float)amount
{
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0;
    CGFloat r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    [a getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [b getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * amount
                            green:g1 + (g2 - g1) * amount
                             blue:b1 + (b2 - b1) * amount
                            alpha:a1 + (a2 - a1) * amount];
}

- (UIColor *)colorForIntensity:(float)intensity
{
    NSInteger index = (NSInteger)(intensity * (self.colorMapSize - 1));
    index = MAX(0, MIN((NSInteger)self.colorMapSize - 1, index));
    return self.colorMap[(NSUInteger)index];
}

@end

#pragma mark - Renderer

@implementation AIRMapHeatmapRenderer

// Standard two-pass density heatmap (same technique GMUHeatmapTileLayer/heatmap.js/the old
// pjamrozowicz fork all use): accumulate weighted points into a grayscale intensity buffer with
// additive blending (so overlapping points intensify instead of just alpha-compositing), then walk
// that buffer through a gradient color ramp to produce the final tinted image. Doing it this way
// (rather than directly drawing overlapping colored radial-gradient circles) avoids visible seams
// where blobs of different colors overlap.
- (void)drawMapRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale inContext:(CGContextRef)context
{
    AIRMapHeatmap *heatmap = (AIRMapHeatmap *)self.overlay;
    NSArray<NSDictionary *> *points = heatmap.points;
    if (points.count == 0) {
        return;
    }

    // Rasterize against the overlay's full boundingMapRect (not the small per-call `mapRect` tile),
    // matching AIRMapOverlayRenderer's pattern: the flip transform below is anchored at this rect's
    // own origin/height, so drawing the same full image on every tile call and letting MapKit's
    // per-tile clip do the cropping is what keeps it correctly positioned. Using the tile-local
    // `mapRect` instead (as this used to) put the flip's anchor at the wrong origin and drew every
    // tile's content outside that tile's own clip region, so nothing ever became visible.
    CGRect rect = [self rectForMapRect:self.overlay.boundingMapRect];
    if (rect.size.width <= 0 || rect.size.height <= 0) {
        return;
    }

    // Cap the raster size regardless of zoom/area so a very zoomed-out view (huge boundingMapRect)
    // can't allocate an unbounded buffer. The cap must scale width/height by the same factor —
    // clamping each dimension independently would desync `bufferScale` (derived from width alone,
    // see below) from the actual height scale whenever only one side needed clamping, stretching
    // blobs into rectangles instead of circles.
    //
    // Previously this also applied a blanket 0.5x downsample "for performance" on top of the cap,
    // but for a zoomed-out preview (small `zoomScale`) the *natural* (undownsampled) raster is
    // already far below the cap — e.g. a whole-day route's boundingMapRect at zoomScale ~0.00024
    // works out to roughly 220x56px natural size, and the blanket downsample was halving that again
    // to ~110x28px for no reason (nowhere near needing the cap), which is coarse enough that a
    // single dense point cluster can occupy just a few buffer pixels — reading as a blocky/hard-edged
    // blob once upscaled back to the full `rect` instead of a smooth one. Only scale down when the
    // natural resolution would actually exceed `maxDimension`.
    CGFloat rawScale = zoomScale;
    size_t maxDimension = 2048;
    CGFloat maxRawDimension = MAX(rect.size.width, rect.size.height) * rawScale;
    if (maxRawDimension > (CGFloat)maxDimension) {
        rawScale *= (CGFloat)maxDimension / maxRawDimension;
    }
    size_t pixelWidth = (size_t)MAX(1.0, round(rect.size.width * rawScale));
    size_t pixelHeight = (size_t)MAX(1.0, round(rect.size.height * rawScale));

    CGFloat pointRadius = heatmap.radius > 0 ? (CGFloat)heatmap.radius : 20.0;
    // `radius` is meant to stay a constant on-screen size regardless of zoom (matching Android's
    // GMUHeatmapTileLayer/the current JS radius semantics) — dividing by zoomScale converts that
    // screen-point radius into this draw call's local (map-point) coordinate space.
    CGFloat mapPointRadius = pointRadius / zoomScale;
    CGFloat bufferScale = (CGFloat)pixelWidth / rect.size.width;
    CGFloat bufferRadius = MAX(1.0, mapPointRadius * bufferScale);

    CGColorSpaceRef grayColorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef intensityContext = CGBitmapContextCreate(NULL, pixelWidth, pixelHeight, 8, pixelWidth,
                                                           grayColorSpace, kCGImageAlphaNone);
    CGColorSpaceRelease(grayColorSpace);
    if (!intensityContext) {
        return;
    }
    // CGBitmapContextCreate defaults to Quartz's bottom-up coordinate system (y increases upward),
    // but `pointForMapPoint:`/`rectForMapRect:` (and therefore `local` below) use MapKit/UIKit's
    // top-down convention (y increases southward/downward). Flip this context's CTM once up front
    // so drawing with those `local` coordinates lands each blob at its correct row instead of its
    // north-south mirror image.
    CGContextTranslateCTM(intensityContext, 0, pixelHeight);
    CGContextScaleCTM(intensityContext, 1.0, -1.0);
    CGContextSetBlendMode(intensityContext, kCGBlendModeScreen);

    // A single, isolated point's blob still peaks at its own exact center by definition, but capping
    // that peak well below 1.0 keeps a lone/sparse point from immediately reading as the gradient's
    // hottest ("solid red") color — Screen-blending still lets genuinely overlapping/dense points
    // climb back up toward 1.0, so real hot spots still read as hot. Without this cap, iOS reads
    // noticeably more saturated than Android's GMUHeatmapTileLayer, which auto-normalizes intensity
    // against the whole dataset instead of a single point's local peak.
    //
    // A live GPS track samples many points along a short, continuous path (consecutive fixes a
    // few meters apart), so most of a walk overlaps 10+ times over just from normal sampling
    // density, not genuine dwelling/revisiting. With the previous 0.3 peak, Screen-blending
    // saturates to the intensity cap (see MIN(0.8, ...) below) within ~5 overlapping points —
    // meaning nearly the entire route reads as the same hottest color instead of a gradient, which
    // is the "one overly intense blob" look. Lowering this means roughly 15-20 overlapping fixes
    // are needed to reach that same cap, so lightly-traveled stretches read cooler (green/yellow)
    // and only genuinely dense clusters (repeated visits, standing still) read hot (red).
    CGFloat blobPeakIntensity = 0.08;
    CGColorSpaceRef gradientColorSpace = CGColorSpaceCreateDeviceGray();
    CGFloat gradientComponents[] = {blobPeakIntensity, 1.0, 0.0, 1.0}; // capped peak -> transparent
    CGFloat gradientLocations[] = {0.0, 1.0};
    CGGradientRef blobGradient = CGGradientCreateWithColorComponents(gradientColorSpace, gradientComponents,
                                                                      gradientLocations, 2);
    CGColorSpaceRelease(gradientColorSpace);

    CGFloat padding = bufferRadius * 2.0;
    NSMutableArray<NSValue *> *projectedPoints = [NSMutableArray arrayWithCapacity:points.count];
    NSMutableArray<NSNumber *> *projectedWeights = [NSMutableArray arrayWithCapacity:points.count];
    float maxWeight = 0;

    for (NSDictionary *pointDict in points) {
        CLLocationCoordinate2D coordinate = [RCTConvert CLLocationCoordinate2D:pointDict];
        MKMapPoint mapPoint = MKMapPointForCoordinate(coordinate);
        CGPoint drawPoint = [self pointForMapPoint:mapPoint];
        CGPoint local = CGPointMake((drawPoint.x - rect.origin.x) * bufferScale,
                                     (drawPoint.y - rect.origin.y) * bufferScale);
        if (local.x < -padding || local.x > (CGFloat)pixelWidth + padding ||
            local.y < -padding || local.y > (CGFloat)pixelHeight + padding) {
            continue;
        }
        float weight = 1.0;
        if (pointDict[@"weight"] != nil) {
            weight = [RCTConvert float:pointDict[@"weight"]];
        }
        maxWeight = MAX(maxWeight, weight);
        [projectedPoints addObject:[NSValue valueWithCGPoint:local]];
        [projectedWeights addObject:@(weight)];
    }

    if (projectedPoints.count == 0) {
        CGContextRelease(intensityContext);
        CGGradientRelease(blobGradient);
        return;
    }
    if (maxWeight <= 0) {
        maxWeight = 1;
    }

    for (NSUInteger i = 0; i < projectedPoints.count; i++) {
        CGPoint local = [projectedPoints[i] CGPointValue];
        float normalizedWeight = [projectedWeights[i] floatValue] / maxWeight;
        CGFloat blobRadius = bufferRadius * (0.6 + sqrt(MAX(0.0, normalizedWeight)) * 0.6);
        CGContextDrawRadialGradient(intensityContext, blobGradient, local, 0, local, blobRadius,
                                     kCGGradientDrawsBeforeStartLocation);
    }
    CGGradientRelease(blobGradient);

    CGImageRef intensityImage = CGBitmapContextCreateImage(intensityContext);
    CGContextRelease(intensityContext);
    if (!intensityImage) {
        return;
    }

    AIRMapHeatmapGradient *gradient = [[AIRMapHeatmapGradient alloc] initWithDictionary:heatmap.gradient];
    float globalOpacity = heatmap.opacity > 0 ? heatmap.opacity : 0.7;

    size_t grayBytesPerRow = CGImageGetBytesPerRow(intensityImage);
    CGDataProviderRef dataProvider = CGImageGetDataProvider(intensityImage);
    CFDataRef rawData = CGDataProviderCopyData(dataProvider);
    const UInt8 *grayPixels = CFDataGetBytePtr(rawData);

    size_t colorBytesPerRow = pixelWidth * 4;
    UInt8 *colorPixels = (UInt8 *)calloc(pixelHeight * colorBytesPerRow, sizeof(UInt8));

    for (size_t y = 0; y < pixelHeight; y++) {
        for (size_t x = 0; x < pixelWidth; x++) {
            UInt8 intensityByte = grayPixels[y * grayBytesPerRow + x];
            if (intensityByte == 0) {
                continue;
            }
            // Cap the accumulated intensity below full scale so even a dense, heavily-overlapping
            // cluster stops short of the gradient's hottest color/full opacity — matches Android's
            // GMUHeatmapTileLayer, which never lets the whole dataset's densest spot fully saturate.
            float intensity = MIN(0.8f, intensityByte / 255.0f);
            UIColor *color = [gradient colorForIntensity:intensity];
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [color getRed:&r green:&g blue:&b alpha:&a];
            float finalAlpha = (float)a * intensity * globalOpacity;
            size_t offset = y * colorBytesPerRow + x * 4;
            // Premultiplied RGBA, matching kCGImageAlphaPremultipliedLast used below.
            colorPixels[offset + 0] = (UInt8)((float)r * finalAlpha * 255.0f);
            colorPixels[offset + 1] = (UInt8)((float)g * finalAlpha * 255.0f);
            colorPixels[offset + 2] = (UInt8)((float)b * finalAlpha * 255.0f);
            colorPixels[offset + 3] = (UInt8)(finalAlpha * 255.0f);
        }
    }
    CFRelease(rawData);
    CGImageRelease(intensityImage);

    // `colorPixels` is a caller-owned buffer (not allocated by CG), so CGBitmapContextCreate wraps
    // it directly rather than copying it — freeing it must wait until after the derived CGImage is
    // completely done being used (drawn + released), since CGBitmapContextCreateImage's "avoid a
    // copy where possible" behavior means the image may still be reading from this exact memory.
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef colorContext = CGBitmapContextCreate(colorPixels, pixelWidth, pixelHeight, 8, colorBytesPerRow,
                                                        rgbColorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgbColorSpace);
    if (!colorContext) {
        free(colorPixels);
        return;
    }
    CGImageRef colorImage = CGBitmapContextCreateImage(colorContext);
    CGContextRelease(colorContext);
    if (!colorImage) {
        free(colorPixels);
        return;
    }

    // Verified-correct image-drawing transform for this library's MKOverlayRenderer contexts —
    // copied from AIRMapOverlayRenderer.m (the plain image-overlay renderer already shipping in
    // react-native-maps), which draws a CGImage into the exact same kind of context this renderer
    // receives. Without this flip, CGContextDrawImage renders upside down here.
    CGContextSaveGState(context);
    // At very small zoom scales (e.g. a small, fully-zoomed-out preview map) `pixelWidth`/`pixelHeight`
    // above can end up tiny (tens of pixels), so this image gets stretched a lot to fill `rect` —
    // without explicit high-quality interpolation that upscale looks blocky/square instead of a soft
    // circular blob.
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextRotateCTM(context, M_PI);
    CGContextScaleCTM(context, -1.0, 1.0);
    CGContextTranslateCTM(context, 0.0, -rect.size.height);
    CGContextDrawImage(context, rect, colorImage);
    CGContextRestoreGState(context);

    CGImageRelease(colorImage);
    free(colorPixels);
}

@end
