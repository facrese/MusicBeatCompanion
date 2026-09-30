#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "BeatService.h"

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

    NSString *path = [NSBundle.mainBundle pathForResource:@"AuthCapture" ofType:@"js"];
    NSString *source = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    WKUserContentController *controller = [WKUserContentController new];
    if (source.length) [controller addUserScript:[[WKUserScript alloc] initWithSource:source
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [controller addScriptMessageHandler:self name:@"beatAuth"];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.userContentController = controller;
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    BeatService.shared.cookieStore = configuration.websiteDataStore.httpCookieStore;
    [self.view addSubview:self.webView];

    self.hint = [UILabel new];
    self.hint.text = @"Войди в Apple Music здесь. После загрузки страницы вернись к компаньону — токены остаются только в памяти приложения.";
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
    NSURL *url = [NSURL URLWithString:@"https://music.apple.com/tr/album/birds-of-a-feather/1739659134?i=1739659142"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.frameInfo.securityOrigin.host.lowercaseString isEqualToString:@"music.apple.com"] ||
        ![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *payload = message.body;
    if (![payload[@"headers"] isKindOfClass:NSDictionary.class] ||
        ![payload[@"url"] isKindOfClass:NSString.class]) return;
    [BeatService.shared acceptWebHeaders:payload[@"headers"] url:payload[@"url"]];
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
