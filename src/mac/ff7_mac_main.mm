// ff7_mac_main.mm - the macOS app: a Cocoa window with a CAMetalLayer for bgfx (Metal), the
// keyboard and game controllers folded into one XInput-style pad, and the lifted game on its
// own thread (ff7_boot_and_run), as src/android/ff7_android_main.cpp does on Android.
//
// The game folder is <app>/Contents/Resources/game when the app carries one, else the folder in
// FF7_GAME_DIR, else ~/Library/Application Support/FF7Recomp/game.
//
// Keyboard (the pad the game sees):
//   arrows       D-pad              Enter / K   OK (Circle)
//   Backspace/J  Cancel (Cross)     Space / I   Menu (Triangle)
//   Shift / U    Square             Q / W       L1 / R1
//   1 / 2        L2 / R2            Tab         Select     P   Start
//   L / R        L3 / R3 (L3: FFNx's shortcut mode: then W/Q speed, Enter battles, Backspace battle+)
//   Cmd+F        fullscreen         Cmd+Q       quit        Cmd+L / Select+Start held 2 s: back to the launcher
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <CoreHaptics/CoreHaptics.h>
#include <atomic>
#include <chrono>
#include <thread>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <pthread.h>
#include <unistd.h>
#include "ff7_boot.h"

namespace {

std::mutex g_lock;
CAMetalLayer *g_layer;
std::atomic<int> g_width{ 1280 }, g_height{ 960 };
std::string g_game_dir;

// keyboard -> XInput bits
std::atomic<unsigned short> g_key_buttons{ 0 };
std::atomic<unsigned char> g_key_lt{ 0 }, g_key_rt{ 0 };
std::atomic<unsigned short> g_inject{ 0 };
std::atomic<bool> g_autofire{ false };
// Back to the launcher: WM_CLOSE to the game's window (on the game thread, as the window's close
// button ends it on Windows), then a fresh instance of the app opens on the launcher.
std::atomic<bool> g_quit{ false };
std::atomic<bool> g_relaunch{ true };
std::chrono::steady_clock::time_point g_leave_held;   // Select+Start held since

enum : unsigned short {
    XI_UP = 0x0001, XI_DOWN = 0x0002, XI_LEFT = 0x0004, XI_RIGHT = 0x0008,
    XI_START = 0x0010, XI_BACK = 0x0020, XI_LTHUMB = 0x0040, XI_RTHUMB = 0x0080,
    XI_LB = 0x0100, XI_RB = 0x0200, XI_A = 0x1000, XI_B = 0x2000, XI_X = 0x4000, XI_Y = 0x8000,
};

// macOS virtual key codes (Carbon kVK_*)
unsigned short key_to_button(unsigned short kc) {
    switch (kc) {
    case 126: return XI_UP;
    case 125: return XI_DOWN;
    case 123: return XI_LEFT;
    case 124: return XI_RIGHT;
    case 36: case 76: case 40: return XI_B;     // Return, keypad Enter, K: OK
    case 51: case 38: return XI_A;              // Backspace, J: cancel
    case 49: case 34: return XI_Y;              // Space, I: menu
    case 32: return XI_X;                       // U: square
    case 12: return XI_LB;                      // Q
    case 13: return XI_RB;                      // W
    case 48: return XI_BACK;                    // Tab: select
    case 35: return XI_START;                   // P: start
    case 37: return XI_LTHUMB;                  // L: L3 (FFNx's shortcut mode)
    case 15: return XI_RTHUMB;                  // R: R3
    default: return 0;
    }
}

// Tests: FF7_TEST_INPUT="seconds:hexbuttons:ms,..." presses XInput buttons at those times
// (e.g. "12:2000:150" taps OK 12 s after start), as the keyboard would.
void *test_input_thread(void *arg) {
    std::string script = static_cast<const char *>(arg);
    auto t0 = std::chrono::steady_clock::now();
    size_t at = 0;
    while (at < script.size()) {
        size_t end = script.find(',', at);
        std::string item = script.substr(at, end == std::string::npos ? std::string::npos : end - at);
        at = end == std::string::npos ? script.size() : end + 1;
        double sec = 0; unsigned btn = 0, ms = 100;
        if (std::sscanf(item.c_str(), "%lf:%x:%u", &sec, &btn, &ms) < 2) continue;
        std::this_thread::sleep_until(t0 + std::chrono::milliseconds((long)(sec * 1000)));
        g_key_buttons.fetch_or((unsigned short)btn);
        std::this_thread::sleep_for(std::chrono::milliseconds(ms));
        g_key_buttons.fetch_and((unsigned short)~btn);
    }
    return nullptr;
}

void relaunch_and_quit() {
    if (g_relaunch.load()) {
        NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
        cfg.createsNewApplicationInstance = YES;
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:[[NSBundle mainBundle] bundleURL] configuration:cfg
                                          completionHandler:^(NSRunningApplication *, NSError *) {
            dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        }];
    } else {
        [NSApp terminate:nil];
    }
}

// The game ended (ExitProcess, src/hle/ff7_kernel32.c): the process ends right after, so the
// launcher is opened now, from the game thread, and waited for.
extern "C" void ff7_platform_exit(int code) {
    std::fprintf(stderr, "[ff7] game exited (%d)%s\n", code, g_relaunch.load() ? ": opening the launcher" : "");
    std::fflush(stderr);
    if (!g_relaunch.load()) return;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[[NSBundle mainBundle] bundleURL] configuration:cfg
                                      completionHandler:^(NSRunningApplication *, NSError *) { dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
}

void *game_thread(void *) {
    int rc = ff7_boot_and_run(g_game_dir.c_str());
    std::fprintf(stderr, "[ff7] game finished with %d\n", rc);
    std::fflush(stderr);
    dispatch_async(dispatch_get_main_queue(), ^{ relaunch_and_quit(); });
    return nullptr;
}

std::string find_game_dir() {
    if (const char *e = getenv("FF7_GAME_DIR")) return e;
    NSString *res = [[NSBundle mainBundle] resourcePath];
    NSString *inApp = [res stringByAppendingPathComponent:@"game"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[inApp stringByAppendingPathComponent:@"ff7_en.exe"]])
        return inApp.UTF8String;
    NSString *sup = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [[sup stringByAppendingPathComponent:@"FF7Recomp/game"] UTF8String];
}

void redirect_log(const std::string &dir) {
    std::string log = dir + "/../ff7.log";
    std::rename(log.c_str(), (dir + "/../ff7.prev.log").c_str());
    if (!getenv("FF7_LOG_STDERR")) {
        freopen(log.c_str(), "w", stderr);
        setvbuf(stderr, nullptr, _IONBF, 0);
    }
}

}  // namespace

// ---- the platform API (src/host/ff7_boot.h) ----

extern "C" void *ff7_platform_window(int *width, int *height) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (width) *width = g_width;
    if (height) *height = g_height;
    return (__bridge void *)g_layer;
}

extern "C" void *ff7_platform_frame_window(void) {
    std::lock_guard<std::mutex> lk(g_lock);
    return (__bridge void *)g_layer;
}

extern "C" void *ff7_platform_companion_window(int *width, int *height) {
    if (width) *width = 0;
    if (height) *height = 0;
    return nullptr;
}

extern "C" int ff7_platform_keyboard_state(unsigned char keys[256]) {
    std::memset(keys, 0, 256);   // the keyboard drives the pad (see the top of this file)
    return 0;
}

static short axis(float v) {
    float c = v * 32767.0f;
    return (short)(c > 32767.0f ? 32767 : c < -32768.0f ? -32768 : c);
}

extern "C" void hle_post_message(uint32_t hwnd, uint32_t message, uint32_t wParam, uint32_t lParam);
extern "C" uint32_t hle_first_hwnd(void);

// The launcher, from the game: the menu, the window's close button, or Select+Start held 2 s.
void request_back_to_launcher() {
    if (g_quit.exchange(true)) return;
    std::fprintf(stderr, "[ff7] back to the launcher\n");
    // a game that does not end within a few seconds is left anyway
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ relaunch_and_quit(); });
}

extern "C" int ff7_platform_pad_state(unsigned index, ff7_pad_state *out) {
    if (index != 0) return 0;
    static bool quit_sent;
    if (g_quit.load() && !quit_sent) {
        quit_sent = true;
        if (uint32_t hwnd = hle_first_hwnd()) hle_post_message(hwnd, 0x0010u /* WM_CLOSE */, 0, 0);
    }
    std::memset(out, 0, sizeof *out);
    out->buttons = g_key_buttons.load() | g_inject.load();
    out->left_trigger = g_key_lt.load();
    out->right_trigger = g_key_rt.load();
    @autoreleasepool {
        for (GCController *c in [GCController controllers]) {
            GCExtendedGamepad *g = c.extendedGamepad;
            if (!g) continue;
            unsigned short b = 0;
            if (g.dpad.up.pressed) b |= XI_UP;
            if (g.dpad.down.pressed) b |= XI_DOWN;
            if (g.dpad.left.pressed) b |= XI_LEFT;
            if (g.dpad.right.pressed) b |= XI_RIGHT;
            if (g.buttonA.pressed) b |= XI_A;
            if (g.buttonB.pressed) b |= XI_B;
            if (g.buttonX.pressed) b |= XI_X;
            if (g.buttonY.pressed) b |= XI_Y;
            if (g.leftShoulder.pressed) b |= XI_LB;
            if (g.rightShoulder.pressed) b |= XI_RB;
            if (g.buttonMenu.pressed) b |= XI_START;
            if (g.buttonOptions && g.buttonOptions.pressed) b |= XI_BACK;
            if (g.leftThumbstickButton && g.leftThumbstickButton.pressed) b |= XI_LTHUMB;
            if (g.rightThumbstickButton && g.rightThumbstickButton.pressed) b |= XI_RTHUMB;
            out->buttons |= b;
            unsigned char lt = (unsigned char)(g.leftTrigger.value * 255.0f);
            unsigned char rt = (unsigned char)(g.rightTrigger.value * 255.0f);
            if (lt > out->left_trigger) out->left_trigger = lt;
            if (rt > out->right_trigger) out->right_trigger = rt;
            out->lx = axis(g.leftThumbstick.xAxis.value);
            out->ly = axis(g.leftThumbstick.yAxis.value);
            out->rx = axis(g.rightThumbstick.xAxis.value);
            out->ry = axis(g.rightThumbstick.yAxis.value);
            break;
        }
    }
    // Select+Start held 2 s: back to the launcher
    const auto now = std::chrono::steady_clock::now();
    if ((out->buttons & (XI_BACK | XI_START)) == (XI_BACK | XI_START)) {
        if (g_leave_held == std::chrono::steady_clock::time_point{}) g_leave_held = now;
        else if (now - g_leave_held > std::chrono::seconds(2)) {
            g_leave_held = {};
            dispatch_async(dispatch_get_main_queue(), ^{ request_back_to_launcher(); });
        }
    } else {
        g_leave_held = {};
    }
    return 1;
}

extern "C" void ff7_platform_pad_rumble(unsigned, unsigned short, unsigned short) {}
// Rumble (src/ffnx_port/rumble.cpp: hits, falls, field shakes): the first controller's haptics.
// amplitude 1..255 for ms, 0 stops. Called on the game thread; played on a serial queue.
static dispatch_queue_t g_rumble_q;
static CHHapticEngine *g_haptics API_AVAILABLE(macos(11.0));
static id<CHHapticPatternPlayer> g_rumble_player API_AVAILABLE(macos(11.0));
static GCController *g_haptics_pad;

extern "C" void ff7_platform_rumble(int amplitude, int ms) {
    if (@available(macOS 11.0, *)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ g_rumble_q = dispatch_queue_create("ff7.rumble", DISPATCH_QUEUE_SERIAL); });
        dispatch_async(g_rumble_q, ^{
            @autoreleasepool {
                GCController *pad = nil;
                for (GCController *c in [GCController controllers]) if (c.haptics) { pad = c; break; }
                if (pad != g_haptics_pad) {
                    [g_haptics stopWithCompletionHandler:nil];
                    g_haptics = pad ? [pad.haptics createEngineWithLocality:GCHapticsLocalityDefault] : nil;
                    g_haptics_pad = pad;
                    g_rumble_player = nil;
                    if (g_haptics) {
                        g_haptics.playsHapticsOnly = YES;
                        g_haptics.resetHandler = ^{ [g_haptics startAndReturnError:nil]; };
                        NSError *e = nil;
                        if (![g_haptics startAndReturnError:&e]) { std::fprintf(stderr, "[rumble] haptics: %s\n", e.localizedDescription.UTF8String); g_haptics = nil; }
                        else std::fprintf(stderr, "[rumble] controller: %s\n", pad.vendorName.UTF8String ?: "?");
                    }
                }
                if (!g_haptics) return;
                [g_rumble_player stopAtTime:CHHapticTimeImmediate error:nil];
                g_rumble_player = nil;
                if (amplitude <= 0 || ms <= 0) return;
                float k = amplitude / 255.0f;
                CHHapticEvent *ev = [[CHHapticEvent alloc]
                    initWithEventType:CHHapticEventTypeHapticContinuous
                           parameters:@[ [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:k],
                                         [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:0.4f] ]
                         relativeTime:0 duration:ms / 1000.0];
                NSError *e = nil;
                CHHapticPattern *pat = [[CHHapticPattern alloc] initWithEvents:@[ ev ] parameters:@[] error:&e];
                if (!pat) return;
                g_rumble_player = [g_haptics createPlayerWithPattern:pat error:&e];
                [g_rumble_player startAtTime:CHHapticTimeImmediate error:&e];
            }
        });
    }
}
extern "C" void ff7_platform_pad_autofire(int on) { g_autofire.store(on != 0); }
extern "C" void ff7_platform_pad_inject(unsigned short buttons) { g_inject.store(buttons); }
extern "C" int ff7_platform_pad_buttons(void) { return g_key_buttons.load(); }

// ---- Cocoa ----

@interface FF7View : NSView
@end

@implementation FF7View
- (BOOL)wantsUpdateLayer { return YES; }
- (CALayer *)makeBackingLayer {
    CAMetalLayer *l = [CAMetalLayer layer];
    l.device = MTLCreateSystemDefaultDevice();
    l.pixelFormat = MTLPixelFormatBGRA8Unorm;
    return l;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)setKey:(NSEvent *)e down:(BOOL)down {
    unsigned short kc = e.keyCode;
    if (kc == 18) { g_key_lt.store(down ? 255 : 0); return; }   // 1: L2
    if (kc == 19) { g_key_rt.store(down ? 255 : 0); return; }   // 2: R2
    unsigned short b = key_to_button(kc);
    if (!b) return;
    if (down) g_key_buttons.fetch_or(b);
    else g_key_buttons.fetch_and((unsigned short)~b);
}
- (void)keyDown:(NSEvent *)e {
    if (e.modifierFlags & NSEventModifierFlagCommand) { [super keyDown:e]; return; }
    [self setKey:e down:YES];
}
- (void)keyUp:(NSEvent *)e { [self setKey:e down:NO]; }
- (void)flagsChanged:(NSEvent *)e {
    if (e.keyCode == 56 || e.keyCode == 60) {   // Shift: square
        BOOL down = (e.modifierFlags & NSEventModifierFlagShift) != 0;
        if (down) g_key_buttons.fetch_or(XI_X);
        else g_key_buttons.fetch_and((unsigned short)~XI_X);
    }
}
- (void)updateDrawableSize {
    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    CGFloat s = self.window.backingScaleFactor;
    l.contentsScale = s;
    CGSize sz = CGSizeMake(self.bounds.size.width * s, self.bounds.size.height * s);
    l.drawableSize = sz;
    g_width = (int)sz.width;
    g_height = (int)sz.height;
}
- (void)setFrameSize:(NSSize)n { [super setFrameSize:n]; [self updateDrawableSize]; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; [self updateDrawableSize]; }
@end

@interface FF7AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) NSWindow *window;
@end

extern "C" void ff7_launcher_show(void);   // src/mac/launcher/Views.swift
extern "C" void ff7_overlay_attach(void *view);   // src/mac/launcher/GameOverlay.swift

@implementation FF7AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    // The launcher first (settings, mods); FF7_QUICKBOOT or FF7_NO_LAUNCHER (tests) go straight in.
    if (getenv("FF7_QUICKBOOT") || getenv("FF7_NO_LAUNCHER")) [self startGameAspect:(getenv("FF7_ASPECT") ? atoi(getenv("FF7_ASPECT")) : 0) fullscreen:NO];
    else ff7_launcher_show();
    [NSApp activateIgnoringOtherApps:YES];
}
// aspect: FFNx aspect_ratio (0 4:3, 1 stretched, 2 16:9, 3 16:10, 4 21:9)
- (void)startGameAspect:(int)aspect fullscreen:(BOOL)fullscreen {
    [self startGameAspect:aspect fullscreen:fullscreen screen:nil];
}
// screen: the display to play on (an AirPlay display macOS uses as a separate display, a TV, a
// second monitor), by name; nil or not found: the main display.
- (void)startGameAspect:(int)aspect fullscreen:(BOOL)fullscreen screen:(NSString *)screenName {
    if (self.window) return;
    NSScreen *target = nil;
    for (NSScreen *sc in [NSScreen screens]) if (screenName.length && [sc.localizedName isEqualToString:screenName]) target = sc;
    NSRect r = aspect == 2 ? NSMakeRect(0, 0, 1600, 900) : aspect == 3 ? NSMakeRect(0, 0, 1440, 900)
             : aspect == 4 ? NSMakeRect(0, 0, 1707, 720) : NSMakeRect(0, 0, 1280, 960);   // 4: 21:9 (64:27)
    self.window = [[NSWindow alloc] initWithContentRect:r
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"FINAL FANTASY VII (FF7Recomp)";
    self.window.delegate = self;
    if (aspect != 1) self.window.contentAspectRatio = r.size;   // stretched: any shape
    FF7View *v = [[FF7View alloc] initWithFrame:r];
    v.wantsLayer = YES;
    self.window.contentView = v;
    if (target) {
        NSRect vf = target.visibleFrame;
        NSRect wf = [self.window frameRectForContentRect:r];
        if (wf.size.width > vf.size.width || wf.size.height > vf.size.height) {
            CGFloat k = MIN(vf.size.width / wf.size.width, vf.size.height / wf.size.height) * 0.9;
            [self.window setContentSize:NSMakeSize(r.size.width * k, r.size.height * k)];
            wf = self.window.frame;
        }
        [self.window setFrameOrigin:NSMakePoint(NSMidX(vf) - wf.size.width / 2, NSMidY(vf) - wf.size.height / 2)];
    } else {
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:v];
    [v updateDrawableSize];
    ff7_overlay_attach((__bridge void *)v);   // booster icons, achievement banner
    {
        std::lock_guard<std::mutex> lk(g_lock);
        g_layer = (CAMetalLayer *)v.layer;
    }
    [NSApp activateIgnoringOtherApps:YES];

    g_game_dir = find_game_dir();
    redirect_log(g_game_dir);
    std::fprintf(stderr, "[ff7] macOS: game folder %s, window %dx%d\n", g_game_dir.c_str(), g_width.load(), g_height.load());
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setstacksize(&a, 64u << 20);   // the lifted game's host stack
    pthread_t t;
    pthread_create(&t, &a, game_thread, nullptr);
    pthread_detach(t);
    if (const char *ti = getenv("FF7_TEST_INPUT")) { pthread_t ti_t; pthread_create(&ti_t, nullptr, test_input_thread, (void *)ti); pthread_detach(ti_t); }
    if (fullscreen) [self.window toggleFullScreen:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
- (BOOL)windowShouldClose:(NSWindow *)w {
    if (w != self.window) return YES;
    request_back_to_launcher();                       // the game ends, the launcher comes back
    return NO;
}
- (void)backToLauncher:(id)sender { if (self.window) request_back_to_launcher(); }
- (void)quitApp:(id)sender { g_relaunch.store(false); [NSApp terminate:nil]; }
@end

static void build_menu(void) {
    NSMenu *bar = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [bar addItem:appItem];
    NSMenu *app = [NSMenu new];
    [app addItemWithTitle:@"Toggle Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Back to Launcher" action:@selector(backToLauncher:) keyEquivalent:@"l"];
    [app addItemWithTitle:@"Quit FF7Recomp" action:@selector(quitApp:) keyEquivalent:@"q"];
    appItem.submenu = app;
    NSApp.mainMenu = bar;
}

int main(int argc, const char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        build_menu();
        FF7AppDelegate *d = [FF7AppDelegate new];
        NSApp.delegate = d;
        [NSApp run];
    }
    return 0;
}

// The launcher's Play (src/mac/launcher/Views.swift).
extern "C" void ff7_mac_start_game(int aspect, int fullscreen, const char *screen) {
    [(FF7AppDelegate *)NSApp.delegate startGameAspect:aspect fullscreen:fullscreen != 0
                                               screen:screen && *screen ? [NSString stringWithUTF8String:screen] : nil];
}

// patches/bgfx/0004 keeps a Vulkan start-up trace; there is no Vulkan renderer here.
extern "C" const char *ff7_bgfx_vk_trace() { return "(Metal)\n"; }
