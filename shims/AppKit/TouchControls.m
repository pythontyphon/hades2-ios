// On-screen gamepad fallback. A UIKit overlay drives an SDL *virtual* joystick laid out like an Xbox
// pad, so the game sees an ordinary controller (and shows Xbox prompts, matching the labels here).
// HadesTouchControls: "auto" (default; shown only while no physical controller is connected),
// "on" or "off".
#import <GameController/GameController.h>
#import "AppKitShim.h"
#include "SDL.h"

#pragma mark - SDL virtual pad

static SDL_Joystick *sPad;
static int sPadDevice = -1;

static BOOL AttachPad(void)
{
    if (sPad) return YES;
    if (!SDL_WasInit(SDL_INIT_JOYSTICK)) return NO;   // game hasn't initialised input yet
    SDL_VirtualJoystickDesc d;
    SDL_zero(d);
    d.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    d.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    d.naxes = SDL_CONTROLLER_AXIS_MAX;
    d.nbuttons = SDL_CONTROLLER_BUTTON_DPAD_RIGHT + 1;
    d.axis_mask = (1u << SDL_CONTROLLER_AXIS_MAX) - 1;
    d.button_mask = (1u << d.nbuttons) - 1;      // joystick button i == controller button i
    d.name = "Hades Touch Controls";
    sPadDevice = SDL_JoystickAttachVirtualEx(&d);
    if (sPadDevice < 0) { SHIM_LOG("touch: attach failed: %s", SDL_GetError()); return NO; }
    sPad = SDL_JoystickOpen(sPadDevice);
    // Triggers rest at -32768 on SDL joysticks; the gamecontroller layer maps that to 0.
    SDL_JoystickSetVirtualAxis(sPad, SDL_CONTROLLER_AXIS_TRIGGERLEFT, -32768);
    SDL_JoystickSetVirtualAxis(sPad, SDL_CONTROLLER_AXIS_TRIGGERRIGHT, -32768);
    SHIM_LOG("touch: virtual pad attached (device %d)", sPadDevice);
    return YES;
}

static void DetachPad(void)
{
    if (!sPad) return;
    SDL_JoystickClose(sPad);
    for (int i = 0; i < SDL_NumJoysticks(); i++)
        if (SDL_JoystickIsVirtual(i)) { SDL_JoystickDetachVirtual(i); break; }
    sPad = NULL;
    SHIM_LOG("touch: virtual pad detached");
}

static void SetButton(int b, BOOL down)
{
    if (!sPad) return;
    if (b == SDL_CONTROLLER_AXIS_TRIGGERLEFT + 100 || b == SDL_CONTROLLER_AXIS_TRIGGERRIGHT + 100)
        SDL_JoystickSetVirtualAxis(sPad, b - 100, down ? 32767 : -32768);   // triggers are axes
    else
        SDL_JoystickSetVirtualButton(sPad, b, down);
}

#pragma mark - Overlay

@interface HadesPadButton : NSObject
@property (nonatomic) int code;               // SDL button, or trigger axis + 100
@property (nonatomic) CGPoint center;
@property (nonatomic) CGFloat radius;
@property (nonatomic, strong) CAShapeLayer *shape;
@property (nonatomic, strong) CATextLayer *label;
@property (nonatomic, weak) UITouch *touch;
@end
@implementation HadesPadButton
@end

@interface HadesTouchOverlay : UIView
@end

@implementation HadesTouchOverlay {
    NSArray<HadesPadButton *> *_buttons;
    UITouch *_stickTouch;
    CGPoint _stickOrigin;
    CAShapeLayer *_stickBase, *_stickKnob;
}

static const CGFloat kStickRadius = 64;

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.clearColor;
        _stickBase = [self circleLayer:kStickRadius alpha:0.10];
        _stickKnob = [self circleLayer:28 alpha:0.35];
        _stickBase.hidden = _stickKnob.hidden = YES;
        [self.layer addSublayer:_stickBase];
        [self.layer addSublayer:_stickKnob];
        NSMutableArray *b = [NSMutableArray new];
        struct { int code; const char *title; CGFloat r; } defs[] = {
            { SDL_CONTROLLER_BUTTON_A, "A", 34 }, { SDL_CONTROLLER_BUTTON_B, "B", 34 },
            { SDL_CONTROLLER_BUTTON_X, "X", 34 }, { SDL_CONTROLLER_BUTTON_Y, "Y", 34 },
            { SDL_CONTROLLER_BUTTON_LEFTSHOULDER, "LB", 24 }, { SDL_CONTROLLER_AXIS_TRIGGERLEFT + 100, "LT", 24 },
            { SDL_CONTROLLER_BUTTON_RIGHTSHOULDER, "RB", 24 }, { SDL_CONTROLLER_AXIS_TRIGGERRIGHT + 100, "RT", 24 },
            { SDL_CONTROLLER_BUTTON_BACK, "⧉", 18 }, { SDL_CONTROLLER_BUTTON_START, "☰", 18 },
        };
        for (size_t i = 0; i < sizeof defs / sizeof *defs; i++) {
            HadesPadButton *pb = [HadesPadButton new];
            pb.code = defs[i].code;
            pb.radius = defs[i].r;
            pb.shape = [self circleLayer:pb.radius alpha:0.16];
            pb.label = [CATextLayer layer];
            pb.label.string = @(defs[i].title);
            pb.label.fontSize = pb.radius * 0.75;
            pb.label.alignmentMode = kCAAlignmentCenter;
            pb.label.foregroundColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
            pb.label.contentsScale = 3;
            [self.layer addSublayer:pb.shape];
            [self.layer addSublayer:pb.label];
            [b addObject:pb];
        }
        _buttons = b;
    }
    return self;
}

- (CAShapeLayer *)circleLayer:(CGFloat)r alpha:(CGFloat)a
{
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-r, -r, 2 * r, 2 * r)].CGPath;
    l.fillColor = [UIColor colorWithWhite:1 alpha:a].CGColor;
    l.strokeColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
    l.lineWidth = 1.5;
    return l;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    UIEdgeInsets in = self.safeAreaInsets;
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat right = W - in.right, left = in.left, bottom = H - MAX(in.bottom, 8);
    CGPoint face = CGPointMake(right - 96, bottom - 104);
    CGFloat s = 66;
    CGPoint pos[] = {
        { face.x, face.y + s }, { face.x + s, face.y }, { face.x - s, face.y }, { face.x, face.y - s },   // A B X Y
        { left + 44, 44 }, { left + 104, 44 },                                                             // LB LT
        { right - 104, 44 }, { right - 44, 44 },                                                           // RB RT
        { W / 2 - 34, 26 }, { W / 2 + 34, 26 },                                                            // Back Start
    };
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        HadesPadButton *pb = _buttons[i];
        pb.center = pos[i];
        pb.shape.position = pb.center;
        CGFloat h = pb.label.fontSize * 1.25;
        pb.label.frame = CGRectMake(pb.center.x - pb.radius, pb.center.y - h / 2, 2 * pb.radius, h);
    }
    [CATransaction commit];
}

- (HadesPadButton *)buttonAt:(CGPoint)p
{
    HadesPadButton *best = nil;
    CGFloat bestD = CGFLOAT_MAX;
    for (HadesPadButton *pb in _buttons) {
        CGFloat d = hypot(p.x - pb.center.x, p.y - pb.center.y);
        if (d < pb.radius + 14 && d < bestD) { best = pb; bestD = d; }   // generous hit slop
    }
    return best;
}

- (void)setPressed:(HadesPadButton *)pb down:(BOOL)down
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    pb.shape.fillColor = [UIColor colorWithWhite:1 alpha:down ? 0.45 : 0.16].CGColor;
    [CATransaction commit];
    SetButton(pb.code, down);
}

- (void)updateStick:(CGPoint)p
{
    CGFloat dx = p.x - _stickOrigin.x, dy = p.y - _stickOrigin.y, len = hypot(dx, dy);
    if (len > kStickRadius) { dx *= kStickRadius / len; dy *= kStickRadius / len; }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _stickKnob.position = CGPointMake(_stickOrigin.x + dx, _stickOrigin.y + dy);
    [CATransaction commit];
    if (sPad) {
        SDL_JoystickSetVirtualAxis(sPad, SDL_CONTROLLER_AXIS_LEFTX, (Sint16)(dx / kStickRadius * 32767));
        SDL_JoystickSetVirtualAxis(sPad, SDL_CONTROLLER_AXIS_LEFTY, (Sint16)(dy / kStickRadius * 32767));
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    AttachPad();
    for (UITouch *t in touches) {
        CGPoint p = [t locationInView:self];
        HadesPadButton *pb = [self buttonAt:p];
        if (pb && !pb.touch) {
            pb.touch = t;
            [self setPressed:pb down:YES];
        } else if (!_stickTouch && p.x < self.bounds.size.width * 0.5) {
            _stickTouch = t;
            _stickOrigin = p;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _stickBase.position = _stickKnob.position = p;
            _stickBase.hidden = _stickKnob.hidden = NO;
            [CATransaction commit];
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *t in touches)
        if (t == _stickTouch) [self updateStick:[t locationInView:self]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (UITouch *t in touches) {
        if (t == _stickTouch) {
            _stickTouch = nil;
            _stickBase.hidden = _stickKnob.hidden = YES;
            [self updateStick:_stickOrigin];   // recentre
        }
        for (HadesPadButton *pb in _buttons)
            if (pb.touch == t) { pb.touch = nil; [self setPressed:pb down:NO]; }
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self touchesEnded:touches withEvent:event];
}
@end

#pragma mark - Visibility

static HadesTouchOverlay *sOverlay;

static BOOL WantOverlay(void)
{
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"HadesTouchControls"] ?: @"auto";
    if ([mode isEqualToString:@"on"]) return YES;
    if ([mode isEqualToString:@"off"]) return NO;
    return GCController.controllers.count == 0;   // our SDL virtual pad is not a GCController
}

static void UpdateOverlay(void)
{
    BOOL want = WantOverlay();
    sOverlay.hidden = !want;
    if (want) {
        if (!AttachPad()) {   // SDL not up yet: retry shortly
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ UpdateOverlay(); });
        }
    } else {
        DetachPad();
    }
}

void HadesInstallTouchControls(UIWindow *window)
{
    sOverlay = [[HadesTouchOverlay alloc] initWithFrame:window.bounds];
    sOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:sOverlay];   // above the root view controller's view (and the game)
    for (NSString *name in @[ GCControllerDidConnectNotification, GCControllerDidDisconnectNotification ])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *n) { UpdateOverlay(); }];
    UpdateOverlay();
}

// SDL on iOS exposes the accelerometer as joystick 0 by default; this game has no use for it and it
// would sit in front of real/virtual pads. Hints must be set before the game calls SDL_Init.
__attribute__((constructor)) static void DisableAccelerometerJoystick(void)
{
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
}
