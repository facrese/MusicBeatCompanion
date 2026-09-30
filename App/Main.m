#import <UIKit/UIKit.h>
#import "BeatService.h"

extern UIViewController *BHCreateWebAuthController(void);

@interface MainViewController : UIViewController
@property (nonatomic, strong) UILabel *trackLabel;
@property (nonatomic, strong) UILabel *authLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@end

@implementation MainViewController

- (UILabel *)labelWithSize:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 12;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *title = [self labelWithSize:29 color:UIColor.labelColor];
    title.font = [UIFont boldSystemFontOfSize:29];
    title.text = @"Music Beat Companion";
    UILabel *subtitle = [self labelWithSize:14 color:UIColor.secondaryLabelColor];
    subtitle.text = @"Стоковая Music остаётся без изменений. Здесь — бит-карта и хаптик. Фоновая работа экспериментальная.";
    self.trackLabel = [self labelWithSize:18 color:UIColor.labelColor];
    self.authLabel = [self labelWithSize:15 color:UIColor.secondaryLabelColor];
    self.statusLabel = [self labelWithSize:15 color:UIColor.secondaryLabelColor];
    self.toggleButton = [self button:@"Включить хаптик" action:@selector(toggle)];
    UIButton *web = [self button:@"Войти через Apple Music Web" action:@selector(openWeb)];
    UIButton *test = [self button:@"Тест вибрации" action:@selector(testPulse)];
    UILabel *hint = [self labelWithSize:13 color:UIColor.tertiaryLabelColor];
    hint.text = @"1. Разреши доступ к медиатеке. 2. Войди в Apple Music Web в этом приложении. 3. Запусти трек в обычной Music. Секреты не вшиты в IPA и не записываются в журнал.";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, subtitle, self.trackLabel, self.authLabel, self.statusLabel,
        self.toggleButton, web, test, hint
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20]
    ]];
    __weak typeof(self) weakSelf = self;
    BeatService.shared.onChange = ^{ [weakSelf refresh]; };
    [self refresh];
}

- (void)refresh {
    BeatService *service = BeatService.shared;
    self.trackLabel.text = service.trackText;
    self.authLabel.text = service.authText;
    self.statusLabel.text = service.statusText;
    [self.toggleButton setTitle:service.enabled ? @"Выключить хаптик" : @"Включить хаптик"
                       forState:UIControlStateNormal];
}

- (void)toggle {
    if (BeatService.shared.enabled) [BeatService.shared stop];
    else [BeatService.shared start];
    [self refresh];
}

- (void)openWeb { [self presentViewController:BHCreateWebAuthController() animated:YES completion:nil]; }
- (void)testPulse { [BeatService.shared testPulse]; }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [MainViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
