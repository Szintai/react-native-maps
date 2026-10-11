//
//  AIRMapPulseRing.m
//
//  See AIRMapPulseRing.h for the root-cause writeup.
//

#import "AIRMapPulseRing.h"

static NSString *const AIRMapPulseRingAnimationKey = @"air-map-pulse-ring-pulse";

@implementation AIRMapPulseRing {
    CAShapeLayer *_ringLayer;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.enabled = NO;
        self.canShowCallout = NO;

        _ringLayer = [CAShapeLayer layer];
        _ringLayer.fillColor = [UIColor clearColor].CGColor;
        _ringLayer.strokeColor = nil;
        _ringLayer.anchorPoint = CGPointMake(0.5, 0.5);
        [self.layer addSublayer:_ringLayer];

        _baseRadius = 1;
        _maxRadius = 1;
        _pulseDurationMs = 1200;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(handleAppDidBecomeActive)
                                                      name:UIApplicationDidBecomeActiveNotification
                                                    object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(handleAppWillResignActive)
                                                      name:UIApplicationWillResignActiveNotification
                                                    object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleAppDidBecomeActive
{
    [self restartPulse];
}

- (void)handleAppWillResignActive
{
    [_ringLayer removeAnimationForKey:AIRMapPulseRingAnimationKey];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _ringLayer.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)rebuildRingPath
{
    CGFloat diameter = MAX(self.maxRadius, 1) * 2;
    CGRect ringBounds = CGRectMake(0, 0, diameter, diameter);
    _ringLayer.bounds = ringBounds;
    _ringLayer.path = [UIBezierPath bezierPathWithOvalInRect:ringBounds].CGPath;
    _ringLayer.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)setRingColor:(UIColor *)ringColor
{
    _ringColor = ringColor;
    _ringLayer.fillColor = ringColor.CGColor;
}

- (void)setBaseRadius:(CGFloat)baseRadius
{
    _baseRadius = baseRadius;
    [self applySizeChange];
}

- (void)setMaxRadius:(CGFloat)maxRadius
{
    _maxRadius = maxRadius;
    [self applySizeChange];
}

- (void)applySizeChange
{
    CGFloat diameter = MAX(self.maxRadius, 1) * 2;
    self.bounds = CGRectMake(0, 0, diameter, diameter);
    [self rebuildRingPath];
    [self restartPulse];
}

- (void)setPulseDurationMs:(NSInteger)pulseDurationMs
{
    _pulseDurationMs = pulseDurationMs;
    [self restartPulse];
}

- (void)restartPulse
{
    [_ringLayer removeAnimationForKey:AIRMapPulseRingAnimationKey];

    if (self.maxRadius <= 0 || self.pulseDurationMs <= 0) {
        return;
    }

    CGFloat fromScale = self.baseRadius / self.maxRadius;
    fromScale = MAX(0.01, MIN(1.0, fromScale));

    CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scaleAnimation.fromValue = @(fromScale);
    scaleAnimation.toValue = @1.0;
    scaleAnimation.duration = self.pulseDurationMs / 1000.0;
    scaleAnimation.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.25f :0.46f :0.45f :0.94f];
    scaleAnimation.repeatCount = HUGE_VALF;
    scaleAnimation.fillMode = kCAFillModeForwards;
    scaleAnimation.removedOnCompletion = NO;

    [_ringLayer addAnimation:scaleAnimation forKey:AIRMapPulseRingAnimationKey];
}

- (MKAnnotationView *)getAnnotationView
{
    return self;
}

- (NSString *)title
{
    return nil;
}

- (NSString *)subtitle
{
    return nil;
}

@end
