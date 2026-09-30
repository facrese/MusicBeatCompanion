#import "BeatService.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreHaptics/CoreHaptics.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <math.h>
#import <string.h>

static NSString *const BHEnabledKey = @"BeatCompanionEnabled";

static BOOL BHValidID(NSString *value) {
    return value.length > 0 && value.length <= 20 &&
        [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

static NSString *BHHeader(NSDictionary *headers, NSString *wanted) {
    for (NSString *key in headers) {
        if ([key caseInsensitiveCompare:wanted] == NSOrderedSame &&
            [headers[key] isKindOfClass:NSString.class]) return headers[key];
    }
    return nil;
}

static NSDictionary *BHAnalysisObject(id value, NSUInteger depth) {
    if (depth > 9) return nil;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = value;
        if ([dictionary[@"beatsInMilliseconds"] isKindOfClass:NSArray.class]) return dictionary;
        for (id child in dictionary.allValues) {
            NSDictionary *found = BHAnalysisObject(child, depth + 1);
            if (found) return found;
        }
    } else if ([value isKindOfClass:NSArray.class]) {
        for (id child in value) {
            NSDictionary *found = BHAnalysisObject(child, depth + 1);
            if (found) return found;
        }
    }
    return nil;
}

static NSArray<NSNumber *> *BHMilliseconds(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSNumber *> *result = NSMutableArray.array;
    NSInteger previous = -1;
    for (id item in value) {
        if (![item isKindOfClass:NSNumber.class]) continue;
        NSInteger ms = [item integerValue];
        if (ms >= 0 && ms <= 36000000 && ms > previous) {
            [result addObject:@(ms)];
            previous = ms;
        }
    }
    return result;
}

@interface BeatService ()
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, copy, readwrite) NSString *statusText;
@property (nonatomic, copy, readwrite) NSString *trackText;
@property (nonatomic, copy, readwrite) NSString *authText;
@property (nonatomic, strong) MPMusicPlayerController *music;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *songID;
@property (nonatomic, copy) NSString *storefront;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *headers;
@property (nonatomic, copy) NSArray<NSNumber *> *beats;
@property (nonatomic, copy) NSArray<NSNumber *> *bars;
@property (nonatomic, strong) CHHapticEngine *engine;
@property (nonatomic, strong) id<CHHapticAdvancedPatternPlayer> patternPlayer;
@property (nonatomic, strong) AVAudioPlayer *keepAlive;
@property (nonatomic) BOOL fetching;
@property (nonatomic) BOOL hapticsPlaying;
@property (nonatomic) NSTimeInterval anchorPosition;
@property (nonatomic) CFTimeInterval anchorTime;
@property (nonatomic) CFTimeInterval retryAfter;
@end

@implementation BeatService

+ (instancetype)shared {
    static BeatService *service;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ service = [BeatService new]; });
    return service;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _headers = NSMutableDictionary.dictionary;
    _storefront = @"tr";
    _statusText = @"Ожидание запуска";
    _trackText = @"Текущий трек: —";
    _authText = @"Web-авторизация: не получена";
    _enabled = [NSUserDefaults.standardUserDefaults boolForKey:BHEnabledKey];
    _timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(tick)
                                   userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tick)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    if (_enabled) dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
    return self;
}

- (void)publish:(NSString *)status {
    self.statusText = status;
    if (self.onChange) self.onChange();
}

- (BOOL)authorizedForLibrary {
    return MPMediaLibrary.authorizationStatus == MPMediaLibraryAuthorizationStatusAuthorized;
}

- (void)start {
    self.enabled = YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:BHEnabledKey];
    MPMediaLibraryAuthorizationStatus authorization = MPMediaLibrary.authorizationStatus;
    if (authorization == MPMediaLibraryAuthorizationStatusNotDetermined) {
        [self publish:@"Разреши доступ к медиатеке для определения трека"];
        [MPMediaLibrary requestAuthorization:^(MPMediaLibraryAuthorizationStatus result) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
        }];
        return;
    }
    if (![self authorizedForLibrary]) {
        [self publish:@"Нет доступа к медиатеке — разреши его в Настройках iOS"];
        return;
    }
    if (!self.music) self.music = MPMusicPlayerController.systemMusicPlayer;
    [self tick];
}

- (void)stopHaptics {
    if (self.patternPlayer) [self.patternPlayer stopAtTime:CHHapticTimeImmediate error:nil];
    self.patternPlayer = nil;
    self.hapticsPlaying = NO;
}

- (void)stopKeepAlive {
    [self.keepAlive stop];
    self.keepAlive = nil;
}

- (void)stop {
    self.enabled = NO;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:BHEnabledKey];
    [self stopHaptics];
    [self stopKeepAlive];
    [self publish:@"Хаптик выключен"];
}

- (NSURL *)cacheURLForSong:(NSString *)songID {
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory
                                                         inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [cache URLByAppendingPathComponent:@"BeatMaps" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES
                                            attributes:nil error:nil];
    return [folder URLByAppendingPathComponent:[songID stringByAppendingString:@".json"]];
}

- (void)acceptAnalysisData:(NSData *)data songID:(NSString *)songID cache:(BOOL)cache {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *object = BHAnalysisObject(json, 0);
    NSArray *beats = BHMilliseconds(object[@"beatsInMilliseconds"]);
    NSArray *bars = BHMilliseconds(object[@"barsInMilliseconds"]);
    if (beats.count == 0 || ![songID isEqualToString:self.songID]) return;
    self.beats = beats;
    self.bars = bars;
    if (cache) [data writeToURL:[self cacheURLForSong:songID] atomically:YES];
    [self publish:[NSString stringWithFormat:@"Карта загружена: %lu ударов, %lu тактов",
                   (unsigned long)beats.count, (unsigned long)bars.count]];
    [self tick];
}

- (void)acceptWebHeaders:(NSDictionary<NSString *,NSString *> *)headers url:(NSString *)url {
    NSAssert([NSThread isMainThread], @"Web headers must be handled on the main thread");
    NSURL *parsed = [NSURL URLWithString:url];
    if (![parsed.host.lowercaseString isEqualToString:@"amp-api.music.apple.com"]) return;
    for (NSString *key in @[@"Authorization", @"media-user-token", @"x-apple-client-version"]) {
        NSString *value = BHHeader(headers, key);
        if (value.length > 0 && value.length < 12000) self.headers[key] = value;
    }
    NSArray *parts = parsed.pathComponents;
    NSUInteger index = [parts indexOfObject:@"catalog"];
    if (index != NSNotFound && index + 1 < parts.count) {
        NSString *candidate = parts[index + 1];
        if (candidate.length == 2) self.storefront = candidate;
    }
    BOOL ready = self.headers[@"Authorization"].length > 0 &&
                 self.headers[@"media-user-token"].length > 0;
    self.authText = ready ? @"Web-авторизация: получена" : @"Web-авторизация: ожидается вход";
    if (self.onChange) self.onChange();
    if (ready && self.songID && !self.beats.count && !self.fetching) [self fetchAnalysis];
}

- (void)fetchAnalysis {
    if (!BHValidID(self.songID) || self.fetching ||
        self.headers[@"Authorization"].length == 0 ||
        self.headers[@"media-user-token"].length == 0 ||
        CACurrentMediaTime() < self.retryAfter) return;
    self.fetching = YES;
    self.retryAfter = CACurrentMediaTime() + 20;
    NSString *songID = self.songID;
    NSString *url = [NSString stringWithFormat:
        @"https://amp-api.music.apple.com/v1/catalog/%@/songs/%@?include=audio-analysis",
        self.storefront ?: @"tr", songID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.timeoutInterval = 20;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"https://music.apple.com" forHTTPHeaderField:@"Origin"];
    [request setValue:@"https://music.apple.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_1 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
       forHTTPHeaderField:@"User-Agent"];
    for (NSString *key in self.headers) [request setValue:self.headers[key] forHTTPHeaderField:key];
    [self publish:@"Загружаю beat map…"];
    void (^send)(NSArray<NSHTTPCookie *> *) = ^(NSArray<NSHTTPCookie *> *cookies) {
        NSMutableArray *selected = NSMutableArray.array;
        for (NSHTTPCookie *cookie in cookies) {
            NSString *domain = [cookie.domain hasPrefix:@"."] ?
                [cookie.domain substringFromIndex:1] : cookie.domain;
            if ([domain isEqualToString:@"music.apple.com"] ||
                [domain isEqualToString:@"amp-api.music.apple.com"]) [selected addObject:cookie];
        }
        NSString *cookieHeader = [NSHTTPCookie requestHeaderFieldsWithCookies:selected][@"Cookie"];
        if (cookieHeader.length) [request setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.fetching = NO;
                if (![self.songID isEqualToString:songID]) return;
                if (status == 200 && data.length) {
                    [self acceptAnalysisData:data songID:songID cache:YES];
                }
                if (!self.beats.count) {
                    [self publish:[NSString stringWithFormat:@"Beat map недоступна: HTTP %ld%@",
                        (long)status, error ? [NSString stringWithFormat:@", %@", error.localizedDescription] : @""]];
                }
            });
        }];
        [task resume];
    };
    if (self.cookieStore) [self.cookieStore getAllCookies:send];
    else send(@[]);
}

- (void)ensureEngine {
    if (self.engine || !CHHapticEngine.capabilitiesForHardware.supportsHaptics) return;
    NSError *error = nil;
    self.engine = [[CHHapticEngine alloc] initWithAudioSession:nil error:&error];
    if (!self.engine) { [self publish:[NSString stringWithFormat:@"Core Haptics: %@", error]]; return; }
    self.engine.playsHapticsOnly = YES;
    self.engine.autoShutdownEnabled = NO;
    __weak typeof(self) weakSelf = self;
    self.engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf stopHaptics];
            [weakSelf publish:[NSString stringWithFormat:@"Движок остановлен (%ld)", (long)reason]];
        });
    };
    self.engine.resetHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf stopHaptics]; [weakSelf tick]; });
    };
}

- (void)preparePattern {
    if (self.patternPlayer || !self.beats.count) return;
    [self ensureEngine];
    if (!self.engine) return;
    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) {
        [self publish:[NSString stringWithFormat:@"Не стартовал Core Haptics: %@", error]];
        return;
    }
    NSMutableArray<CHHapticEvent *> *events = NSMutableArray.array;
    NSUInteger barIndex = 0;
    for (NSNumber *beat in self.beats) {
        NSInteger ms = beat.integerValue;
        while (barIndex < self.bars.count && self.bars[barIndex].integerValue < ms - 55) barIndex++;
        BOOL accent = barIndex < self.bars.count &&
            labs(self.bars[barIndex].longValue - beat.longValue) <= 55;
        CHHapticEventParameter *intensity = [[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticIntensity value:accent ? 0.72f : 0.38f];
        CHHapticEventParameter *sharpness = [[CHHapticEventParameter alloc]
            initWithParameterID:CHHapticEventParameterIDHapticSharpness value:accent ? 0.62f : 0.46f];
        [events addObject:[[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
            parameters:@[intensity, sharpness] relativeTime:beat.doubleValue / 1000.0]];
    }
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:events parameterCurves:@[] error:&error];
    if (!pattern) { [self publish:[NSString stringWithFormat:@"Ошибка паттерна: %@", error]]; return; }
    self.patternPlayer = [self.engine createAdvancedPlayerWithPattern:pattern error:&error];
    if (!self.patternPlayer) [self publish:[NSString stringWithFormat:@"Ошибка плеера: %@", error]];
}

- (NSData *)silentWAV {
    const uint32_t sampleRate = 8000;
    const uint32_t dataLength = sampleRate * 2;
    NSMutableData *data = [NSMutableData dataWithLength:44 + dataLength];
    uint8_t *bytes = data.mutableBytes;
    memcpy(bytes, "RIFF", 4);
    uint32_t size = 36 + dataLength; memcpy(bytes + 4, &size, 4);
    memcpy(bytes + 8, "WAVEfmt ", 8);
    uint32_t chunk = 16; memcpy(bytes + 16, &chunk, 4);
    uint16_t pcm = 1; memcpy(bytes + 20, &pcm, 2);
    uint16_t channels = 1; memcpy(bytes + 22, &channels, 2);
    memcpy(bytes + 24, &sampleRate, 4);
    uint32_t byteRate = sampleRate * 2; memcpy(bytes + 28, &byteRate, 4);
    uint16_t alignment = 2; memcpy(bytes + 32, &alignment, 2);
    uint16_t bits = 16; memcpy(bytes + 34, &bits, 2);
    memcpy(bytes + 36, "data", 4); memcpy(bytes + 40, &dataLength, 4);
    return data;
}

- (void)startKeepAlive {
    if (self.keepAlive.playing) return;
    NSError *error = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionMixWithOthers error:&error] ||
        ![session setActive:YES error:&error]) {
        [self publish:[NSString stringWithFormat:@"Фоновый звук недоступен: %@", error]];
        return;
    }
    self.keepAlive = [[AVAudioPlayer alloc] initWithData:[self silentWAV] error:&error];
    self.keepAlive.numberOfLoops = -1;
    self.keepAlive.volume = 0;
    if (![self.keepAlive play]) [self publish:[NSString stringWithFormat:@"Фоновое аудио не стартовало: %@", error]];
}

- (void)tick {
    if (!self.enabled || ![self authorizedForLibrary]) return;
    if (!self.music) self.music = MPMusicPlayerController.systemMusicPlayer;
    MPMediaItem *item = self.music.nowPlayingItem;
    NSString *songID = item.playbackStoreID;
    if (!BHValidID(songID)) songID = nil;
    NSString *title = [item valueForProperty:MPMediaItemPropertyTitle] ?: @"—";
    NSString *artist = [item valueForProperty:MPMediaItemPropertyArtist] ?: @"";
    self.trackText = [NSString stringWithFormat:@"%@ — %@\nCatalog ID: %@",
                      artist, title, songID ?: @"нет"];
    if ((songID || self.songID) && ![songID isEqualToString:self.songID]) {
        [self stopHaptics];
        self.songID = songID;
        self.beats = nil;
        self.bars = nil;
        self.fetching = NO;
        self.retryAfter = 0;
        if (songID) {
            NSData *cached = [NSData dataWithContentsOfURL:[self cacheURLForSong:songID]];
            if (cached) [self acceptAnalysisData:cached songID:songID cache:NO];
            if (!self.beats.count) [self fetchAnalysis];
        }
    }
    BOOL playing = self.music.playbackState == MPMusicPlaybackStatePlaying && songID != nil;
    if (!playing) {
        [self stopHaptics];
        [self stopKeepAlive];
        [self publish:songID ? @"Пауза" : @"Ожидание каталожного трека в Music"];
        return;
    }
    [self startKeepAlive];
    if (!self.beats.count) {
        if (self.headers[@"Authorization"].length && !self.fetching) [self fetchAnalysis];
        else if (!self.fetching) [self publish:@"Открой Web-вход для автоматической загрузки beat map"];
        return;
    }
    NSTimeInterval position = self.music.currentPlaybackTime;
    if (!isfinite(position) || position < 0) position = 0;
    [self preparePattern];
    if (!self.patternPlayer) return;
    if (self.hapticsPlaying) {
        NSTimeInterval expected = self.anchorPosition + CACurrentMediaTime() - self.anchorTime;
        if (fabs(expected - position) < 0.6) return;
        [self stopHaptics];
        [self preparePattern];
        if (!self.patternPlayer) return;
    }
    NSError *error = nil;
    if (![self.patternPlayer seekToOffset:position error:&error] ||
        ![self.patternPlayer startAtTime:CHHapticTimeImmediate error:&error]) {
        [self publish:[NSString stringWithFormat:@"Хаптик не стартовал: %@", error]];
        [self stopHaptics];
        return;
    }
    self.hapticsPlaying = YES;
    self.anchorPosition = position;
    self.anchorTime = CACurrentMediaTime();
    [self publish:[NSString stringWithFormat:@"Хаптик играет, позиция %.1f с", position]];
}

- (void)testPulse {
    [self ensureEngine];
    if (!self.engine) return;
    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) {
        [self publish:[NSString stringWithFormat:@"Тест не стартовал: %@", error]];
        return;
    }
    CHHapticEventParameter *strength = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity value:0.8f];
    CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
        parameters:@[strength] relativeTime:0];
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[event]
        parameterCurves:@[] error:&error];
    if (!pattern) {
        [self publish:[NSString stringWithFormat:@"Тест не прошёл: %@", error]];
        return;
    }
    id<CHHapticPatternPlayer> test = [self.engine createPlayerWithPattern:pattern error:&error];
    if (![test startAtTime:CHHapticTimeImmediate error:&error])
        [self publish:[NSString stringWithFormat:@"Тест не прошёл: %@", error]];
    else [self publish:@"Тестовый импульс отправлен"];
}

@end
