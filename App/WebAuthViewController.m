#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "BeatService.h"
#import "WebAuth.h"

static NSURL *BHMusicWebURL(void) {
    return [NSURL URLWithString:@"https://music.apple.com/tr/album/birds-of-a-feather/1739659134?i=1739659142"];
}

static WKWebViewConfiguration *BHWebConfiguration(id<WKScriptMessageHandler> handler) {
    NSString *path = [NSBundle.mainBundle pathForResource:@"AuthCapture" ofType:@"js"];
    NSString *source = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    WKUserContentController *controller = [WKUserContentController new];
    if (source.length) [controller addUserScript:[[WKUserScript alloc] initWithSource:source
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [controller addScriptMessageHandler:handler name:@"beatAuth"];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.userContentController = controller;
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    return configuration;
}

static void BHHandleAuthMessage(WKScriptMessage *message) {
    if (![message.frameInfo.securityOrigin.host.lowercaseString isEqualToString:@"music.apple.com"] ||
        ![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *payload = message.body;
    if (![payload[@"headers"] isKindOfClass:NSDictionary.class] ||
        ![payload[@"url"] isKindOfClass:NSString.class]) return;
    [BeatService.shared acceptWebHeaders:payload[@"headers"] url:payload[@"url"]];
}

@interface BHHiddenWebAuth : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic) NSTimeInterval lastReload;
+ (instancetype)shared;
- (void)attachToHost:(UIView *)host;
- (void)reload;
@end

@implementation BHHiddenWebAuth
+ (instancetype)shared {
    static BHHiddenWebAuth *probe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ probe = [BHHiddenWebAuth new]; });
    return probe;
}
- (void)attachToHost:(UIView *)host {
    if (self.webView) return;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(-2, -2, 1, 1)
        configuration:BHWebConfiguration(self)];
    self.webView.alpha = 0.01;
    self.webView.userInteractionEnabled = NO;
    [host addSubview:self.webView];
    BeatService.shared.cookieStore = self.webView.configuration.websiteDataStore.httpCookieStore;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self reload];
}
- (void)reload {
    if (!self.webView || NSDate.date.timeIntervalSince1970 - self.lastReload < 30) return;
    self.lastReload = NSDate.date.timeIntervalSince1970;
    [self.webView loadRequest:[NSURLRequest requestWithURL:BHMusicWebURL()]];
}
- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    BHHandleAuthMessage(message);
}
@end

@interface WebAuthViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *hint;
@end

@implementation WebAuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"Apple Music Web";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];

    WKWebViewConfiguration *configuration = BHWebConfiguration(self);
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    BeatService.shared.cookieStore = configuration.websiteDataStore.httpCookieStore;
    [self.view addSubview:self.webView];

    self.hint = [UILabel new];
    self.hint.text = @"Войди в Apple Music здесь. После загрузки страницы вернись к компаньону — токены хранятся только в Keychain этого iPhone.";
    self.hint.numberOfLines = 0;
    self.hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.hint.textColor = UIColor.secondaryLabelColor;
    self.hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.hint];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.hint.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.hint.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.webView.topAnchor constraintEqualToAnchor:self.hint.bottomAnchor constant:8],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self reload];
}

- (void)close {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"beatAuth"];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
    [self.webView loadRequest:[NSURLRequest requestWithURL:BHMusicWebURL()]];
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    BHHandleAuthMessage(message);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    self.hint.text = [NSString stringWithFormat:@"Страница не открылась: %@", error.localizedDescription];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    self.hint.text = [NSString stringWithFormat:@"Страница не открылась: %@", error.localizedDescription];
}

- (void)dealloc {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"beatAuth"];
}

@end

UIViewController *BHCreateWebAuthController(void) {
    return [[UINavigationController alloc] initWithRootViewController:[WebAuthViewController new]];
}

void BHWarmWebAuth(UIView *host) { [[BHHiddenWebAuth shared] attachToHost:host]; }

void BHRefreshWebAuth(void) { [[BHHiddenWebAuth shared] reload]; }
