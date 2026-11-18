// Engels Kueche: iOS 12.0+ / iPad Air 1. Generation
// Native UIKit + WKWebView. No private APIs, no third-party framework.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>

static NSString * const EGTouchNotification = @"EGTouchNotification";
static NSString * const EGServerKey = @"EGServerURL";
static NSString * const EGDayKey = @"EGDayStart";
static NSString * const EGNightKey = @"EGNightStart";
static NSString * const EGActiveKey = @"EGActiveBrightness";
static NSString * const EGIdleKey = @"EGIdleBrightness";
static NSString * const EGNightBrightnessKey = @"EGNightBrightness";
static NSString * const EGDelayKey = @"EGIdleMinutes";
static NSString * const EGFrontKey = @"EGFrontCamera";

static void EGRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        EGServerKey:@"", EGDayKey:@"07:10", EGNightKey:@"22:30",
        EGActiveKey:@(100), EGIdleKey:@(30), EGNightBrightnessKey:@(1),
        EGDelayKey:@(30), EGFrontKey:@YES
    }];
}
static NSString *EGServerURL(void) {
    return [[[NSUserDefaults standardUserDefaults] stringForKey:EGServerKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}
static CGFloat EGPercent(NSString *key) {
    NSInteger percent = [[NSUserDefaults standardUserDefaults] integerForKey:key];
    return MIN(1.0, MAX(.01, percent/100.0));
}
static NSInteger EGTimeToMinutes(NSString *time) {
    NSArray *parts = [time componentsSeparatedByString:@":"];
    if (parts.count != 2) return 0;
    return [parts[0] integerValue] * 60 + [parts[1] integerValue];
}
static BOOL EGIsNight(NSDate *date) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger start = EGTimeToMinutes([d stringForKey:EGNightKey]);
    NSInteger end = EGTimeToMinutes([d stringForKey:EGDayKey]);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    NSInteger now = c.hour * 60 + c.minute;
    if (start == end) return NO;
    return start > end ? (now >= start || now < end) : (now >= start && now < end);
}

// UIWindow gets touch notifications without intercepting taps or scrolling in WKWebView.
@interface EGWindow : UIWindow @end
@implementation EGWindow
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase == UITouchPhaseBegan) {
                [[NSNotificationCenter defaultCenter] postNotificationName:EGTouchNotification object:nil];
                break;
            }
        }
    }
    [super sendEvent:event];
}
@end


// Camera capture is independent from Apple's UIImagePickerController, which can
// show a black, unresponsive shutter on older iPadOS/jailbroken devices.
@interface EGCameraController : UIViewController <AVCapturePhotoCaptureDelegate>
@property(nonatomic,copy) void (^photoHandler)(UIImage *);
@property(nonatomic,strong) AVCaptureSession *session;
@property(nonatomic,strong) AVCapturePhotoOutput *photoOutput;
@property(nonatomic,strong) AVCaptureVideoPreviewLayer *preview;
@property(nonatomic,strong) UILabel *hint;
@property(nonatomic,strong) UIButton *shutter;
@property(nonatomic,strong) UIButton *flip;
@property(nonatomic,assign) AVCaptureDevicePosition position;
@property(nonatomic,assign) BOOL takingPhoto;
@end

@implementation EGCameraController
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.position = [[NSUserDefaults standardUserDefaults] boolForKey:EGFrontKey] ?
        AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    self.preview = [AVCaptureVideoPreviewLayer layer];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.preview];

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.7];
    [self.view addSubview:bar];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Abbrechen" forState:UIControlStateNormal];
    [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    cancel.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightMedium];
    [cancel addTarget:self action:@selector(cancelCamera) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:cancel];

    self.flip = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.flip setTitle:@"Kamera wechseln" forState:UIControlStateNormal];
    [self.flip setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.flip.translatesAutoresizingMaskIntoConstraints = NO;
    self.flip.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    [self.flip addTarget:self action:@selector(switchCamera) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:self.flip];

    self.shutter = [UIButton buttonWithType:UIButtonTypeCustom];
    self.shutter.translatesAutoresizingMaskIntoConstraints = NO;
    self.shutter.backgroundColor = UIColor.whiteColor;
    self.shutter.layer.cornerRadius = 34;
    self.shutter.layer.borderColor = UIColor.lightGrayColor.CGColor;
    self.shutter.layer.borderWidth = 4;
    self.shutter.accessibilityLabel = @"Rezept fotografieren";
    self.shutter.enabled = NO;
    [self.shutter addTarget:self action:@selector(takePhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shutter];

    self.hint = [[UILabel alloc] init];
    self.hint.translatesAutoresizingMaskIntoConstraints = NO;
    self.hint.textAlignment = NSTextAlignmentCenter;
    self.hint.numberOfLines = 0;
    self.hint.textColor = UIColor.whiteColor;
    self.hint.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.5];
    self.hint.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.hint.text = @"Kamera startet …";
    [self.view addSubview:self.hint];

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:72],
        [cancel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:18],
        [cancel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.flip.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-18],
        [self.flip.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.shutter.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.shutter.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-30],
        [self.shutter.widthAnchor constraintEqualToConstant:68],
        [self.shutter.heightAnchor constraintEqualToConstant:68],
        [self.hint.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.hint.bottomAnchor constraintEqualToAnchor:self.shutter.topAnchor constant:-24],
        [self.hint.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:.9]
    ]];
    [self checkCameraPermission];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.preview.frame = self.view.bounds;
}
- (void)showCameraMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hint.text = message;
        self.hint.hidden = (message.length == 0);
    });
}
- (void)checkCameraPermission {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) { [self setupCamera]; return; }
    if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL allowed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (allowed) [self setupCamera];
                else [self showCameraMessage:@"Kamerazugriff abgelehnt. Unter Einstellungen > Datenschutz > Kamera für Engels Küche erlauben."];
            });
        }];
        return;
    }
    [self showCameraMessage:@"Kein Kamerazugriff. Bitte unter Einstellungen > Datenschutz > Kamera für Engels Küche erlauben."];
}
- (AVCaptureDevice *)deviceForPosition:(AVCaptureDevicePosition)position {
    return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                              mediaType:AVMediaTypeVideo position:position];
}
- (void)setupCamera {
    AVCaptureDevice *device = [self deviceForPosition:self.position];
    if (!device) {
        [self showCameraMessage:@"Diese Kamera ist nicht verfügbar. Bitte oben Kamera wechseln."];
        self.flip.enabled = YES;
        return;
    }
    self.shutter.enabled = NO;
    self.shutter.alpha = .5;
    self.flip.enabled = NO;
    [self showCameraMessage:@"Kamera startet …"];
    if (self.session) {
        AVCaptureSession *oldSession = self.session;
        self.session = nil;
        self.preview.session = nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [oldSession stopRunning]; });
    }
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetPhoto;
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];
    if (!input || ![session canAddInput:input] || ![session canAddOutput:output]) {
        self.flip.enabled = YES;
        [self showCameraMessage:[NSString stringWithFormat:@"Kamera konnte nicht gestartet werden: %@. Bitte Kamera wechseln oder die normale iPad-Kamera testen.", error.localizedDescription ?: @"Gerät nicht verfügbar"]];
        return;
    }
    [session addInput:input];
    [session addOutput:output];
    self.session = session;
    self.photoOutput = output;
    self.preview.session = session;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.session != session) return;
            self.flip.enabled = YES;
            BOOL ok = session.isRunning;
            self.shutter.enabled = ok;
            self.shutter.alpha = ok ? 1 : .5;
            [self showCameraMessage:ok ? @"" : @"Die Kamera startet nicht. Bitte Kamera wechseln oder die normale Kamera-App des iPads prüfen."];
        });
    });
}
- (void)switchCamera {
    if (self.takingPhoto) return;
    self.position = self.position == AVCaptureDevicePositionFront ?
        AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    [[NSUserDefaults standardUserDefaults] setBool:(self.position == AVCaptureDevicePositionFront) forKey:EGFrontKey];
    [self setupCamera];
}
- (void)takePhoto {
    if (self.takingPhoto || !self.photoOutput || !self.session.isRunning) {
        [self showCameraMessage:@"Kamera noch nicht bereit. Bitte kurz erneut versuchen."];
        return;
    }
    self.takingPhoto = YES;
    self.shutter.enabled = NO;
    self.shutter.alpha = .5;
    [self showCameraMessage:@"Foto wird aufgenommen …"];
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    NSData *data = error ? nil : [photo fileDataRepresentation];
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.takingPhoto = NO;
        self.shutter.enabled = YES;
        self.shutter.alpha = 1;
        if (!image) {
            [self showCameraMessage:[NSString stringWithFormat:@"Foto fehlgeschlagen: %@",error.localizedDescription ?: @"Kein Bild erhalten."]];
            return;
        }
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.photoHandler) self.photoHandler(image);
        }];
    });
}
- (void)cancelCamera {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    AVCaptureSession *session = self.session;
    self.preview.session = nil;
    self.session = nil;
    if (session) dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        [session stopRunning];
    });
}
@end

@class EGKitchenViewController;
@interface EGSettingsViewController : UIViewController <UITextFieldDelegate>
@property(nonatomic,weak) EGKitchenViewController *kitchen;
@end

@interface EGKitchenViewController : UIViewController <WKNavigationDelegate, WKScriptMessageHandler>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UILabel *offlineLabel;
@property(nonatomic,strong) UIButton *settingsButton;
@property(nonatomic,strong) UIView *nightOverlay;
@property(nonatomic,strong) UILabel *nightClockLabel;
@property(nonatomic,strong) NSTimer *clockTimer;
@property(nonatomic,strong) NSDate *lastTouch;
@property(nonatomic,strong) NSDate *nightWakeUntil;
@property(nonatomic,assign) BOOL pausedForSettings;
@property(nonatomic,assign) BOOL isInForeground;
@property(nonatomic,assign) BOOL brightnessRemembered;
@property(nonatomic,assign) CGFloat previousBrightness;
- (void)loadKitchen;
- (void)applyBrightness;
- (void)settingsUpdated;
@end

@interface EGAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) EGWindow *window;
@property(nonatomic,strong) EGKitchenViewController *kitchen;
@end

@implementation EGKitchenViewController
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:.96 green:.96 blue:.93 alpha:1];
    self.lastTouch = [NSDate date];
    self.isInForeground = YES;
    [self makeWebView];
    [self makeControls];
    [self makeNightClock];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(touched) name:EGTouchNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResign) name:UIApplicationWillResignActiveNotification object:nil];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(applyBrightness) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.clockTimer forMode:NSRunLoopCommonModes];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [self loadKitchen];
    [self applyBrightness];
}
- (void)makeWebView {
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *user = [[WKUserContentController alloc] init];
    // WebKit loads this script before other page scripts, so the scan click
    // reaches our native UIImagePickerController rather than the HTML picker.
    NSString *bridge = @"(function(){window.engelsNativeApp=true;"
      @"document.addEventListener('click',function(e){"
      @"var p=e.target;while(p&&p!==document){if(p.id==='photo'){"
      @"e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();"
      @"window.webkit.messageHandlers.engelsKitchen.postMessage({action:'scan'});return;}p=p.parentNode;}"
      @"},true);"
      @"var s=document.createElement('style');s.textContent='#k-display-dimmer,#k-display-settings-button{display:none!important}';"
      @"if(document.documentElement){document.documentElement.appendChild(s);}else{document.addEventListener('DOMContentLoaded',function(){document.documentElement.appendChild(s);});}"
      @"})();";
    [user addUserScript:[[WKUserScript alloc] initWithSource:bridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    [user addScriptMessageHandler:self name:@"engelsKitchen"];
    cfg.userContentController = user;
    self.web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    self.web.translatesAutoresizingMaskIntoConstraints = NO;
    self.web.navigationDelegate = self;
    self.web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.web.opaque = NO;
    self.web.backgroundColor = [UIColor colorWithRed:.97 green:.97 blue:.95 alpha:1];
    [self.view addSubview:self.web];
    [NSLayoutConstraint activateConstraints:@[
        [self.web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.web.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}
- (void)makeControls {
    self.offlineLabel = [[UILabel alloc] init];
    self.offlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.offlineLabel.textAlignment = NSTextAlignmentCenter;
    self.offlineLabel.numberOfLines = 0;
    self.offlineLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    self.offlineLabel.textColor = [UIColor colorWithRed:.21 green:.32 blue:.26 alpha:1];
    self.offlineLabel.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:.95];
    self.offlineLabel.layer.cornerRadius = 14;
    self.offlineLabel.layer.masksToBounds = YES;
    self.offlineLabel.hidden = YES;
    [self.view addSubview:self.offlineLabel];
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsButton.backgroundColor = [[UIColor colorWithRed:.18 green:.40 blue:.27 alpha:1] colorWithAlphaComponent:.92];
    self.settingsButton.layer.cornerRadius = 22;
    [self.settingsButton setTitle:@"⚙" forState:UIControlStateNormal];
    [self.settingsButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.settingsButton.titleLabel.font = [UIFont systemFontOfSize:24];
    self.settingsButton.accessibilityLabel = @"Küchen-App-Einstellungen";
    [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.settingsButton];
    [NSLayoutConstraint activateConstraints:@[
      [self.offlineLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
      [self.offlineLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
      [self.offlineLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:.90],
      [self.offlineLabel.widthAnchor constraintGreaterThanOrEqualToConstant:260],
      [self.offlineLabel.heightAnchor constraintGreaterThanOrEqualToConstant:100],
      [self.settingsButton.widthAnchor constraintEqualToConstant:44],
      [self.settingsButton.heightAnchor constraintEqualToConstant:44],
      [self.settingsButton.rightAnchor constraintEqualToAnchor:self.view.rightAnchor constant:-12],
      [self.settingsButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12]
    ]];
}
// The nighttime view covers every control and the webpage, including the gear.
// One touch wakes the normal kitchen for the configured period.
- (void)makeNightClock {
    self.nightOverlay = [[UIView alloc] init];
    self.nightOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.nightOverlay.backgroundColor = UIColor.blackColor;
    self.nightOverlay.hidden = YES;
    self.nightOverlay.userInteractionEnabled = YES;
    [self.view addSubview:self.nightOverlay];

    self.nightClockLabel = [[UILabel alloc] init];
    self.nightClockLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nightClockLabel.textAlignment = NSTextAlignmentCenter;
    self.nightClockLabel.textColor = UIColor.whiteColor;
    self.nightClockLabel.font = [UIFont monospacedDigitSystemFontOfSize:86 weight:UIFontWeightUltraLight];
    self.nightClockLabel.adjustsFontSizeToFitWidth = YES;
    self.nightClockLabel.minimumScaleFactor = .4;
    [self.nightOverlay addSubview:self.nightClockLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.nightOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.nightOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.nightOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.nightOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.nightClockLabel.centerXAnchor constraintEqualToAnchor:self.nightOverlay.centerXAnchor],
        [self.nightClockLabel.centerYAnchor constraintEqualToAnchor:self.nightOverlay.centerYAnchor],
        [self.nightClockLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.nightOverlay.widthAnchor multiplier:.9]
    ]];
}
- (void)updateNightClock:(NSDate *)date {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    fmt.dateFormat = @"HH:mm";
    self.nightClockLabel.text = [fmt stringFromDate:date];
}
- (void)loadKitchen {
    NSString *address = EGServerURL();
    if (address.length == 0) {
        self.offlineLabel.hidden = NO;
        self.offlineLabel.text = @"Engels Küche\n\nBitte über ⚙ die Adresse des Lenovo-Küchenservers eintragen, z. B. http://192.168.178.100:8091/";
        [self showSettings];
        return;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:address];
    if (!([components.scheme.lowercaseString isEqualToString:@"http"] || [components.scheme.lowercaseString isEqualToString:@"https"]) || !components.host.length) {
        self.offlineLabel.hidden = NO;
        self.offlineLabel.text = @"Die Küchenserver-Adresse ist ungültig. Bitte unter ⚙ korrigieren.";
        return;
    }
    self.offlineLabel.hidden = YES;
    NSURLRequest *request = [NSURLRequest requestWithURL:components.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [self.web loadRequest:request];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.offlineLabel.hidden = YES;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self displayFailure:error];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self displayFailure:error];
}
- (void)displayFailure:(NSError *)error {
    if (error.code == NSURLErrorCancelled) return;
    self.offlineLabel.hidden = NO;
    self.offlineLabel.text = [NSString stringWithFormat:@"Küchenserver nicht erreichbar\n\n%@\n\nPrüfe WLAN und Lenovo-Adresse unter ⚙.\nZum Wiederholen: App-Einstellungen öffnen und ‚Verbinden‘ tippen.", error.localizedDescription ?: @""];
}
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"engelsKitchen"]) return;
    if ([message.body isKindOfClass:[NSDictionary class]] && [message.body[@"action"] isEqual:@"scan"]) [self openCamera];
}
- (void)openCamera {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self showError:@"Dieses iPad meldet keine verfügbare Kamera."];
        return;
    }
    EGCameraController *camera = [[EGCameraController alloc] init];
    __weak typeof(self) weakSelf = self;
    camera.photoHandler = ^(UIImage *image) {
        [weakSelf forwardPhoto:image];
    };
    camera.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:camera animated:YES completion:nil];
}
- (void)forwardPhoto:(UIImage *)image {
    if (!image) { [self showError:@"Kamerafoto konnte nicht gelesen werden."]; return; }
    // Native JPEG resizing avoids huge JS payloads and rotates camera images upright.
    CGFloat maxSide = 2400;
    CGFloat s = MIN(1.0, maxSide / MAX(image.size.width, image.size.height));
    CGSize size = CGSizeMake(MAX(1, round(image.size.width*s)), MAX(1, round(image.size.height*s)));
    UIGraphicsBeginImageContextWithOptions(size, YES, 1);
    [image drawInRect:CGRectMake(0,0,size.width,size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSData *jpeg = UIImageJPEGRepresentation(scaled, .82);
    if (!jpeg) { [self showError:@"Bild konnte nicht als JPEG verarbeitet werden."]; return; }
    NSString *photo = [@"data:image/jpeg;base64," stringByAppendingString:[jpeg base64EncodedStringWithOptions:0]];
    NSString *js = [NSString stringWithFormat:@"(function(){var p='%@'; if(typeof window.kitchenNativeScanPhoto==='function'){window.kitchenNativeScanPhoto(p);return 'ok';}return 'missing';})()", photo];
    [self.web evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error || ![result isEqual:@"ok"]) {
            [self showError:@"Der Küchenserver hat die native Scan-Schnittstelle noch nicht. Bitte zuerst den beiliegenden Lenovo-Patch installieren und die App neu laden."];
        }
    }];
}
- (void)showError:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Engels Küche" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)touched {
    self.lastTouch = [NSDate date];
    if (EGIsNight(self.lastTouch)) {
        NSInteger interval = MAX(1, [[NSUserDefaults standardUserDefaults] integerForKey:EGDelayKey]);
        self.nightWakeUntil = [NSDate dateWithTimeIntervalSinceNow:interval*60];
    }
    [self applyBrightness];
}
- (void)applyBrightness {
    if (!self.isInForeground) return;
    if (!self.brightnessRemembered) {
        self.previousBrightness = [UIScreen mainScreen].brightness;
        self.brightnessRemembered = YES;
    }
    NSDate *now = [NSDate date];
    BOOL night = EGIsNight(now);
    BOOL temporarilyAwake = self.nightWakeUntil &&
        [self.nightWakeUntil compare:now] == NSOrderedDescending;
    BOOL showNight = night && !temporarilyAwake && !self.pausedForSettings;
    if (showNight) [self updateNightClock:now];
    self.nightOverlay.hidden = !showNight;
    CGFloat target = EGPercent(EGActiveKey);
    if (!self.pausedForSettings) {
        if (showNight) target = EGPercent(EGNightBrightnessKey);
        else if (!night) {
            NSInteger minutes = MAX(1, [[NSUserDefaults standardUserDefaults] integerForKey:EGDelayKey]);
            if ([now timeIntervalSinceDate:self.lastTouch] >= minutes*60) target = EGPercent(EGIdleKey);
        }
    }
    if (fabs([UIScreen mainScreen].brightness - target) > .005) [UIScreen mainScreen].brightness = target;
}
- (void)becameActive {
    self.isInForeground = YES;
    self.brightnessRemembered = NO;
    self.lastTouch = [NSDate date];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [self applyBrightness];
}
- (void)willResign {
    self.isInForeground = NO;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    if (self.brightnessRemembered) [UIScreen mainScreen].brightness = self.previousBrightness;
    self.brightnessRemembered = NO;
}
- (void)showSettings {
    self.pausedForSettings = YES;
    [self applyBrightness];
    EGSettingsViewController *settings = [[EGSettingsViewController alloc] init];
    settings.kitchen = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}
- (void)settingsUpdated {
    self.pausedForSettings = NO;
    self.lastTouch = [NSDate date];
    if (EGIsNight(self.lastTouch)) {
        self.nightWakeUntil = [NSDate dateWithTimeIntervalSinceNow:MAX(1, [[NSUserDefaults standardUserDefaults] integerForKey:EGDelayKey])*60];
    }
    [self applyBrightness];
    [self loadKitchen];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.clockTimer invalidate];
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"engelsKitchen"];
}
@end

@interface EGSettingsViewController ()
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UITextField *serverField;
@property(nonatomic,strong) UIDatePicker *dayPicker;
@property(nonatomic,strong) UIDatePicker *nightPicker;
@property(nonatomic,strong) UISlider *activeSlider;
@property(nonatomic,strong) UISlider *idleSlider;
@property(nonatomic,strong) UISlider *nightSlider;
@property(nonatomic,strong) UISlider *durationSlider;
@property(nonatomic,strong) UISwitch *frontSwitch;
@property(nonatomic,strong) NSMutableDictionary<NSString *, UILabel *> *valueLabels;
@end
@implementation EGSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Küchen-Display";
    self.view.backgroundColor = [UIColor colorWithRed:.97 green:.97 blue:.95 alpha:1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Fertig" style:UIBarButtonItemStyleDone target:self action:@selector(saveAndClose)];
    self.valueLabels = [NSMutableDictionary dictionary];
    self.scroll = [[UIScrollView alloc] init]; self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scroll];
    [NSLayoutConstraint activateConstraints:@[
       [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
       [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
       [self.scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
       [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    self.stack = [[UIStackView alloc] init]; self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12; self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.layoutMargins = UIEdgeInsetsMake(16,18,28,18); self.stack.layoutMarginsRelativeArrangement = YES;
    [self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
       [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.leadingAnchor],
       [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.trailingAnchor],
       [self.stack.topAnchor constraintEqualToAnchor:self.scroll.topAnchor],
       [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.bottomAnchor],
       [self.stack.widthAnchor constraintEqualToAnchor:self.scroll.widthAnchor]
    ]];
    [self addText:@"Die echte Bildschirmhelligkeit wird vom iPad gesteuert. Die Einstellungen gelten nur für dieses Gerät." size:14];
    [self addText:@"Lenovo-Küchenserver (WLAN)" size:16];
    self.serverField = [[UITextField alloc] init];
    self.serverField.borderStyle = UITextBorderStyleRoundedRect; self.serverField.font = [UIFont systemFontOfSize:16];
    self.serverField.keyboardType = UIKeyboardTypeURL; self.serverField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.serverField.autocorrectionType = UITextAutocorrectionTypeNo; self.serverField.returnKeyType = UIReturnKeyDone;
    self.serverField.delegate = self; self.serverField.placeholder = @"http://192.168.178.xxx:8091/";
    self.serverField.text = EGServerURL();
    [self.stack addArrangedSubview:self.serverField]; [self.serverField.heightAnchor constraintEqualToConstant:44].active = YES;
    [self addText:@"Tag beginnt" size:16];
    self.dayPicker = [self timePickerFor:EGDayKey]; [self addNarrowTimePicker:self.dayPicker];
    [self addText:@"Nacht beginnt" size:16];
    self.nightPicker = [self timePickerFor:EGNightKey]; [self addNarrowTimePicker:self.nightPicker];
    self.activeSlider = [self addSlider:@"Bei Bedienung" key:EGActiveKey minimum:10 maximum:100 suffix:@" %"];
    self.idleSlider = [self addSlider:@"Nach Inaktivität" key:EGIdleKey minimum:1 maximum:100 suffix:@" %"];
    self.nightSlider = [self addSlider:@"Nachts" key:EGNightBrightnessKey minimum:1 maximum:100 suffix:@" %"];
    self.durationSlider = [self addSlider:@"Nach Berührung hell bleiben" key:EGDelayKey minimum:1 maximum:120 suffix:@" Min."];
    UIStackView *cameraLine = [[UIStackView alloc] init]; cameraLine.axis = UILayoutConstraintAxisHorizontal;
    cameraLine.alignment = UIStackViewAlignmentCenter; cameraLine.spacing = 10;
    UILabel *frontLabel = [[UILabel alloc] init]; frontLabel.text = @"Beim Scannen Frontkamera verwenden";
    frontLabel.font = [UIFont systemFontOfSize:15]; frontLabel.numberOfLines = 0;
    [cameraLine addArrangedSubview:frontLabel];
    self.frontSwitch = [[UISwitch alloc] init]; self.frontSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:EGFrontKey];
    [cameraLine addArrangedSubview:self.frontSwitch]; [self.stack addArrangedSubview:cameraLine];
    [self addText:@"Hinweis: Die Frontkamera des iPad Air liefert eine geringere Fotoauflösung als die Rückkamera. Für sehr kleine Kochbuchschrift kannst du den Schalter ausschalten." size:12];
    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    [retry setTitle:@"Speichern und mit Lenovo verbinden" forState:UIControlStateNormal];
    retry.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    retry.backgroundColor = [UIColor colorWithRed:.19 green:.43 blue:.29 alpha:1];
    [retry setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    retry.layer.cornerRadius = 11; [retry.heightAnchor constraintEqualToConstant:48].active = YES;
    [retry addTarget:self action:@selector(saveAndClose) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:retry];
}
- (void)addText:(NSString *)text size:(CGFloat)size {
    UILabel *l = [[UILabel alloc] init]; l.text = text; l.numberOfLines = 0;
    l.font = [UIFont systemFontOfSize:size]; l.textColor = [UIColor colorWithRed:.16 green:.22 blue:.18 alpha:1];
    [self.stack addArrangedSubview:l];
}
// A narrow date picker leaves the entire right half of the settings page
// available for vertical swipes that won't spin the hour/minute wheels.
- (void)addNarrowTimePicker:(UIDatePicker *)picker {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 0;
    [row addArrangedSubview:picker];
    UIView *scrollGutter = [[UIView alloc] init];
    scrollGutter.userInteractionEnabled = NO;
    [row addArrangedSubview:scrollGutter];
    [self.stack addArrangedSubview:row];
    [picker.widthAnchor constraintEqualToConstant:270].active = YES;
    [row.heightAnchor constraintEqualToConstant:135].active = YES;
}
- (UIDatePicker *)timePickerFor:(NSString *)key {
    UIDatePicker *picker = [[UIDatePicker alloc] init]; picker.datePickerMode = UIDatePickerModeTime;
    picker.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    picker.minuteInterval = 1;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"HH:mm";
    NSDate *d = [fmt dateFromString:[[NSUserDefaults standardUserDefaults] stringForKey:key]];
    if (d) picker.date = d;
    [picker.heightAnchor constraintEqualToConstant:130].active = YES;
    return picker;
}
- (UISlider *)addSlider:(NSString *)label key:(NSString *)key minimum:(NSInteger)minimum maximum:(NSInteger)maximum suffix:(NSString *)suffix {
    UIStackView *group = [[UIStackView alloc] init]; group.axis = UILayoutConstraintAxisVertical; group.spacing = 3;
    UIStackView *head = [[UIStackView alloc] init]; head.axis = UILayoutConstraintAxisHorizontal; head.distribution = UIStackViewDistributionEqualSpacing;
    UILabel *title = [[UILabel alloc] init]; title.text = label; title.font = [UIFont systemFontOfSize:15];
    UILabel *value = [[UILabel alloc] init]; value.font = [UIFont boldSystemFontOfSize:15];
    value.text = [NSString stringWithFormat:@"%ld%@",(long)[[NSUserDefaults standardUserDefaults] integerForKey:key],suffix];
    self.valueLabels[key] = value;
    [head addArrangedSubview:title]; [head addArrangedSubview:value]; [group addArrangedSubview:head];
    UISlider *slider = [[UISlider alloc] init]; slider.minimumValue = minimum; slider.maximumValue = maximum;
    slider.value = [[NSUserDefaults standardUserDefaults] integerForKey:key];
    slider.accessibilityLabel = label;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [group addArrangedSubview:slider]; [self.stack addArrangedSubview:group];
    return slider;
}
- (void)sliderChanged:(UISlider *)sender {
    NSArray *sliders = @[self.activeSlider ?: [NSNull null],self.idleSlider ?: [NSNull null],self.nightSlider ?: [NSNull null],self.durationSlider ?: [NSNull null]];
    NSArray *keys = @[EGActiveKey,EGIdleKey,EGNightBrightnessKey,EGDelayKey];
    for (NSInteger i=0;i<sliders.count;i++) if (sliders[i] == sender) {
        NSInteger p = lroundf(sender.value);
        self.valueLabels[keys[i]].text = [NSString stringWithFormat:@"%ld %@",(long)p,(i==3?@"Min.":@"%")];
    }
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)saveAndClose {
    NSString *address = [[self.serverField.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (address.length && ![address containsString:@"://"]) address = [@"http://" stringByAppendingString:address];
    NSURLComponents *u = [NSURLComponents componentsWithString:address];
    if (address.length && !([u.scheme.lowercaseString isEqualToString:@"http"] || [u.scheme.lowercaseString isEqualToString:@"https"]) ) {
        [self invalidAddress]; return;
    }
    if (address.length && !u.host.length) { [self invalidAddress]; return; }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:address forKey:EGServerKey];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"HH:mm"; fmt.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    [d setObject:[fmt stringFromDate:self.dayPicker.date] forKey:EGDayKey];
    [d setObject:[fmt stringFromDate:self.nightPicker.date] forKey:EGNightKey];
    [d setInteger:lroundf(self.activeSlider.value) forKey:EGActiveKey];
    [d setInteger:lroundf(self.idleSlider.value) forKey:EGIdleKey];
    [d setInteger:lroundf(self.nightSlider.value) forKey:EGNightBrightnessKey];
    [d setInteger:lroundf(self.durationSlider.value) forKey:EGDelayKey];
    [d setBool:self.frontSwitch.isOn forKey:EGFrontKey];
    [self dismissViewControllerAnimated:YES completion:^{ [self.kitchen settingsUpdated]; }];
}
- (void)invalidAddress {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Adresse prüfen" message:@"Bitte eine gültige http://- oder https://-Adresse des Lenovo eingeben." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

@implementation EGAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    EGRegisterDefaults();
    self.window = [[EGWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.kitchen = [[EGKitchenViewController alloc] init];
    self.window.rootViewController = self.kitchen;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, NSStringFromClass([UIApplication class]), NSStringFromClass([EGAppDelegate class]));
    }
}
