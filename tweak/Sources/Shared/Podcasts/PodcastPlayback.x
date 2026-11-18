// Podcasts at playback: a new episode starts at 0:00, and blocked sections are jumped over. The player reports
// a state when the track, pause or loading changes, not as the position moves, so a timer reads the position
// while an episode with blocked sections plays, and for the first seconds of an episode that has to start at 0:00.
#import "Core/SGCore.h"
#import "Podcasts.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"

static const NSTimeInterval kTick = 0.15;
// How long a new episode may take to load before the start at 0:00 gives up waiting for it.
static const CFTimeInterval kStartWindow = 8;
// A position past this on a new episode is where it was left, not where it began.
static const double kLeftOffAfter = 2;
// After a seek the state still reports the old position for a moment; nothing is judged until it has caught up.
static const CFTimeInterval kQuietAfterSeek = 1;

static BOOL isEpisode(NSString *uri) {
    return [uri hasPrefix:@"spotify:episode:"];
}

static SPTPlayerState *playersOwnState(void) {
    id player = SGKaraokePlayer();
    return [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
}

// The state of the episode `uri`, or of whatever episode plays when `uri` is nil. Two sources say what plays, the
// player's own state and the last one it reported, and in some contexts they do not agree on the track (an
// episode played from a playlist, say), so each is tried and the one that is of the episode wins. Nil when
// neither is.
static SPTPlayerState *episodeState(NSString *uri) {
    for (id candidate in @[playersOwnState() ?: NSNull.null, SGPlayerState() ?: NSNull.null]) {
        // Spotify's own class is not linked against, so the answer to "is this a state" is what it responds to.
        if (![candidate respondsToSelector:@selector(track)]) continue;
        SPTPlayerState *state = candidate;
        NSString *playing = SGURIString(state.track.URI);
        if (uri ? [playing isEqualToString:uri] : isEpisode(playing)) return state;
    }
    return nil;
}

NSDictionary *SGPodcastPlayingEpisode(void) {
    SPTPlayerTrack *track = episodeState(nil).track;
    NSString *uri = SGURIString(track.URI);
    if (!isEpisode(uri)) return nil;
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    // Read defensively: an episode's track carries the show where a song's carries the artist and the album.
    NSString *title = track.trackTitle.length ? track.trackTitle : metadata[@"title"];
    NSString *show = [metadata[@"album_title"] isKindOfClass:NSString.class] ? metadata[@"album_title"] : track.artistName;
    return @{
        SGPodcastURI: uri,
        SGPodcastTitle: [title isKindOfClass:NSString.class] && title.length ? title : uri,
        SGPodcastShow: [show isKindOfClass:NSString.class] ? show : @"",
    };
}

double SGPodcastPlayingPosition(void) {
    SPTPlayerState *state = episodeState(nil);
    if (!state) return -1;
    return state.isPaused ? state.positionAsOfTimestamp : state.position;
}

@interface SGPodcastWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGPodcastWatcher {
    NSString *_uri;                // the episode playing, nil for anything else
    BOOL _paused;
    BOOL _checkStart;              // a new episode whose first position has not been read yet
    CFTimeInterval _startedAt, _quietUntil;
    NSString *_skippedOnToNext;    // the episode a skip to the next one was sent for
    NSTimer *_timer;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    // A switch or a block changing while an episode plays takes hold now, not at the next episode.
    __weak SGPodcastWatcher *weak = self;
    void (^refresh)(NSNotification *) = ^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weak update]; });
    };
    [NSNotificationCenter.defaultCenter addObserverForName:SGPodcastBlocksDidChangeNotification object:nil queue:nil usingBlock:refresh];
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:refresh];
    return self;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (!isEpisode(uri)) {
        _uri = nil;
        _checkStart = NO;
        [self update];
        return;
    }
    BOOL fresh = ![uri isEqualToString:_uri];
    BOOL pressedPlay = !fresh && _paused && !state.isPaused;
    _uri = uri;
    _paused = state.isPaused;
    if (fresh) {
        _checkStart = SGFlag(SGKeyPodcastStartAtZero, NO);
        _startedAt = CACurrentMediaTime();
        _quietUntil = 0;
        _skippedOnToNext = nil;
    } else if (pressedPlay && SGFlag(SGKeyPodcastRestartOnPlay, NO)) {
        [self seekTo:0 why:@"play pressed"];
    }
    [self update];
}

- (BOOL)hasBlocks {
    if (!_uri) return NO;
    for (NSDictionary *block in SGPodcastBlocks()) {
        if ([block[SGPodcastURI] isEqualToString:_uri]) return YES;
    }
    return NO;
}

// The timer runs only while there is something to watch for.
- (void)update {
    BOOL watching = _uri && (_checkStart || (SGFlag(SGKeyPodcastBlocker, NO) && !_paused && [self hasBlocks]));
    if (watching && !_timer) {
        __weak SGPodcastWatcher *weak = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:kTick repeats:YES block:^(NSTimer *timer) { [weak tick]; }];
    } else if (!watching && _timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)seekTo:(double)seconds why:(NSString *)why {
    id player = SGKaraokePlayer();
    if (![player respondsToSelector:@selector(seekTo:)]) {
        SGLog(@"podcasts: %@, but no player to seek", why);
        return;
    }
    [(id<SPTPlayer>)player seekTo:seconds];
    _quietUntil = CACurrentMediaTime() + kQuietAfterSeek;
    SGLog(@"podcasts: %@, seek to %@", why, SGPodcastFormatTime(seconds));
}

- (void)tick {
    SPTPlayerState *state = episodeState(_uri);
    if (!_uri || !state) return;
    CFTimeInterval now = CACurrentMediaTime();
    double position = state.isPaused ? state.positionAsOfTimestamp : state.position;
    BOOL loading = [state respondsToSelector:@selector(isLoading)] && state.isLoading;

    if (_checkStart) {
        if (now - _startedAt > kStartWindow) {
            _checkStart = NO;
        } else if (!loading && state.duration > 0) {
            // The first position read once it has loaded: past the first seconds, it is where it was left.
            _checkStart = NO;
            if (position > kLeftOffAfter) {
                [self seekTo:0 why:[NSString stringWithFormat:@"new episode resumed at %@", SGPodcastFormatTime(position)]];
                [self update];
                return;
            }
        }
    }

    if (now < _quietUntil || state.isPaused || !SGFlag(SGKeyPodcastBlocker, NO)) {
        [self update];
        return;
    }
    double to = SGPodcastResumePoint(SGPodcastBlocks(), _uri, position);
    if (isnan(to)) return;
    if (to < 0 || (state.duration > 0 && to >= state.duration - 0.5)) {
        if ([_skippedOnToNext isEqualToString:_uri]) return;
        _skippedOnToNext = _uri;
        id player = SGKaraokePlayer();
        if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:)]) {
            [(id<SPTPlayer>)player skipToNextTrackWithOptions:nil];
            SGLog(@"podcasts: blocked from %@ to the end, skipped to the next", SGPodcastFormatTime(position));
        }
        return;
    }
    [self seekTo:to why:[NSString stringWithFormat:@"blocked at %@", SGPodcastFormatTime(position)]];
}

@end

static SGPodcastWatcher *sg_podcastWatcher;

%ctor {
    sg_podcastWatcher = [SGPodcastWatcher new];
    SGAddPlayerStateObserver(sg_podcastWatcher);
}
