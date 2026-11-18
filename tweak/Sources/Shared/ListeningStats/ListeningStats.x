// ListeningStats.h says what Listening stats is. This is the recording: PlayerState's observer is told
// when the track or playing changes, never the position, so a play's length is the wall-clock time it
// spent playing, and it is written down when the next track takes over.
//
// ponytail: a track on repeat one never changes the state's track, so its replays are not counted, and a
// play cut off by Spotify being killed is lost; position polling would catch both.
#import "Core/SGCore.h"
#import "Shared/Podcasts/Podcasts.h"
#import "Shared/Player/PlayerState.h"
#import "ListeningStats.h"
#import "SGPlayLog.h"

SGPlayLog *SGListeningLog(void) {
    static SGPlayLog *log;
    if (!log) {
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        log = [[SGPlayLog alloc] initWithPath:[support stringByAppendingPathComponent:@"spoti.pw/Listening.tsv"]];
    }
    return log;
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

@interface SGPlayRecorder : NSObject <SGPlayerStateObserver>
@end

@implementation SGPlayRecorder {
    SGPlay *_play;
    double _duration, _listened;
    CFAbsoluteTime _since;   // when it started playing, 0 while it is not
}

// Songs, local files and podcast episodes; not ads or the silence between.
static BOOL isEpisode(NSString *uri) {
    return [uri hasPrefix:@"spotify:episode:"];
}

static BOOL isCounted(NSString *uri) {
    return [uri hasPrefix:@"spotify:track:"] || [uri hasPrefix:@"spotify:local:"] || isEpisode(uri);
}

// The metadata can come after the track does, so what is missing is filled in on every report.
- (void)fill:(SPTPlayerState *)state {
    SPTPlayerTrack *track = state.track;
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (!_play.title.length) _play.title = stringIn(track.trackTitle) ?: stringIn(metadata[@"title"]) ?: @"";
    if (!_play.artist.length) _play.artist = stringIn(metadata[@"artist_name"]) ?: stringIn(track.artistName) ?: @"";
    if (!_play.album.length) _play.album = stringIn(metadata[@"album_title"]) ?: @"";
    // An episode has a show where a song has an artist, so the show is what its minutes are added up under.
    // An episode is credited to who it was named for: the stats add it up with that name's songs.
    if (isEpisode(_play.uri)) _play.artist = SGPodcastCreditFor(_play.title, _play.album) ?: _play.album;
    if (_duration <= 0) _duration = state.duration;
}

- (void)finish {
    if (_play && _play.title.length && _play.artist.length && SGPlayCounts(_listened, _duration) && SGEnabled(SGKeyListeningStats)) {
        _play.end = (int64_t)time(NULL);
        _play.ms = (int64_t)(_listened * 1000);
        [SGListeningLog() record:_play];
    }
    _play = nil;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (_since) _listened += now - _since;
    _since = 0;
    NSString *uri = SGURIString(state.track.URI);
    if (![uri isEqualToString:_play.uri]) {
        [self finish];
        if (isCounted(uri)) {
            _play = [SGPlay new];
            _play.uri = uri;
            _duration = _listened = 0;
        }
    }
    if (!_play) return;
    [self fill:state];
    // A song is written down when the next one takes over, which for an episode may be hours away, so an episode
    // that has run long enough is written down at each pause, and what is heard after it is a play of its own.
    if (isEpisode(_play.uri) && state.isPaused && SGPlayCounts(_listened, _duration)) {
        [self finish];
        return;
    }
    BOOL loading = [state respondsToSelector:@selector(isLoading)] && state.isLoading;
    if (state.isPlaying && !state.isPaused && !loading) _since = now;
}

- (void)terminate {
    if (_since) _listened += CFAbsoluteTimeGetCurrent() - _since;
    _since = 0;
    [self finish];
}

@end

%ctor {
    static SGPlayRecorder *recorder;
    recorder = [SGPlayRecorder new];
    SGAddPlayerStateObserver(recorder);
    [NSNotificationCenter.defaultCenter addObserver:recorder selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
}
