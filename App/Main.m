#import <UIKit/UIKit.h>
#import <math.h>
#import "BeatService.h"
#import "WebAuth.h"

@interface MainViewController : UIViewController
@property (nonatomic, strong) UILabel *trackLabel;
@property (nonatomic, strong) UILabel *authLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *diagnosticLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UILabel *> *sliderValues;
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
    self.sliderValues = NSMutableDictionary.dictionary;
    UILabel *title = [self labelWithSize:29 color:UIColor.labelColor];
    title.font = [UIFont boldSystemFontOfSize:29];
    title.text = @"Music Beat Companion";
    UILabel *subtitle = [self labelWithSize:14 color:UIColor.secondaryLabelColor];
    subtitle.text = @"Оригинальная Music остаётся без изменений. Авторизация восстанавливается автоматически; фон пока экспериментальный.";
    self.trackLabel = [self labelWithSize:18 color:UIColor.labelColor];
    self.authLabel = [self labelWithSize:15 color:UIColor.secondaryLabelColor];
    self.statusLabel = [self labelWithSize:15 color:UIColor.secondaryLabelColor];
    self.diagnosticLabel = [self labelWithSize:13 color:UIColor.tertiaryLabelColor];
    self.toggleButton = [self button:@"Включить хаптик" action:@selector(toggle)];
    UIButton *web = [self button:@"Войти через Apple Music Web" action:@selector(openWeb)];
    UIButton *test = [self button:@"Тест вибрации" action:@selector(testPulse)];
    UILabel *settings = [self labelWithSize:21 color:UIColor.labelColor];
    settings.font = [UIFont boldSystemFontOfSize:21];
    settings.text = @"Настройка ударов";
    UILabel *explanation = [self labelWithSize:13 color:UIColor.secondaryLabelColor];
    explanation.text = @"Сила и тон долей и тактов независимы. «Тон» — это sharpness Core Haptics: мягкий ↔ звонкий, не частота в герцах. Ноль силы выключает соответствующий слой.";
    UILabel *hint = [self labelWithSize:13 color:UIColor.tertiaryLabelColor];
    hint.text = @"Сдвиг +мс запускает хаптик раньше музыки. Web-сеанс хранится в Keychain, запрос beat map выполняется автоматически при смене трека. Если фоновый режим остановится, iOS может ограничивать Core Haptics.";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, subtitle, self.trackLabel, self.authLabel, self.statusLabel,
        self.diagnosticLabel,
        self.toggleButton, web, test, settings, explanation,
        [self sliderRow:@"Доли · сила" value:BeatService.shared.beatIntensity tag:1],
        [self sliderRow:@"Доли · тон" value:BeatService.shared.beatSharpness tag:2],
        [self sliderRow:@"Такты · сила" value:BeatService.shared.barIntensity tag:3],
        [self sliderRow:@"Такты · тон" value:BeatService.shared.barSharpness tag:4],
        [self sliderRow:@"Синхронизация" value:BeatService.shared.timingOffsetMs tag:5],
        hint
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];
    __weak typeof(self) weakSelf = self;
    BeatService.shared.onChange = ^{ [weakSelf refresh]; };
    [self refresh];
    BHWarmWebAuth(self.view);
}

- (UIView *)sliderRow:(NSString *)title value:(float)value tag:(NSInteger)tag {
    UILabel *name = [self labelWithSize:15 color:UIColor.labelColor];
    name.text = title;
    UILabel *readout = [self labelWithSize:14 color:UIColor.secondaryLabelColor];
    readout.textAlignment = NSTextAlignmentRight;
    self.sliderValues[@(tag)] = readout;
    UISlider *slider = [UISlider new];
    slider.tag = tag;
    slider.minimumValue = tag == 5 ? -500 : 0;
    slider.maximumValue = tag == 5 ? 500 : 1;
    slider.value = value;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderReleased:)
       forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[name, readout]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.distribution = UIStackViewDistributionFillEqually;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[header, slider]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 2;
    [self updateReadoutForSlider:slider];
    return row;
}

- (void)updateReadoutForSlider:(UISlider *)slider {
    NSInteger value = slider.tag == 5 ? lroundf(slider.value / 10.0f) * 10 : lroundf(slider.value * 100);
    self.sliderValues[@(slider.tag)].text = slider.tag == 5 ?
        [NSString stringWithFormat:@"%+ld мс", (long)value] :
        [NSString stringWithFormat:@"%ld%%", (long)value];
}

- (void)sliderChanged:(UISlider *)slider { [self updateReadoutForSlider:slider]; }

- (void)sliderReleased:(UISlider *)slider {
    BeatService *service = BeatService.shared;
    switch (slider.tag) {
        case 1: service.beatIntensity = slider.value; break;
        case 2: service.beatSharpness = slider.value; break;
        case 3: service.barIntensity = slider.value; break;
        case 4: service.barSharpness = slider.value; break;
        case 5: service.timingOffsetMs = lroundf(slider.value / 10.0f) * 10; break;
    }
    [self updateReadoutForSlider:slider];
}

- (void)refresh {
    BeatService *service = BeatService.shared;
    self.trackLabel.text = service.trackText;
    self.authLabel.text = service.authText;
    self.statusLabel.text = service.statusText;
    self.diagnosticLabel.text = service.diagnosticText;
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
