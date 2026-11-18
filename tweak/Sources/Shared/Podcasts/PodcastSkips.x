// An episode's skip buttons skip tracks, as a song's do. Spotify gives an episode back and forward 15 seconds
// where a song has previous and next, in the player and on the lock screen. In the player those buttons call the
// playback controller's seekBackwardBySeconds: and seekForwardBySeconds:, which are turned into previous and
// next while an episode plays. On the lock screen the system draws the skip commands as 15 when they are on
// and previous and next when only those are, so the skip commands are turned off and previous and next on.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Podcasts.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTNowPlayingPlaybackController.h"

static __weak SPTNowPlayingPlaybackControllerImplementation *sg_controller;

static NSString *playingURI(void) {
    return SGURIString(SGPlayerState().track.URI);
}

static BOOL episodeSkips(void) {
    return SGEnabled(SGKeyPodcastSkipTracks) && [playingURI() hasPrefix:@"spotify:episode:"];
}

static void skipNext(void) {
    SPTNowPlayingPlaybackControllerImplementation *controller = sg_controller;
    if (controller.canSkipNext) [controller skipToNextWhileDragging:NO];
}

static void skipPrevious(void) {
    [sg_controller skipToPreviousWhileDragging:NO];
}

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client {
    id controller = %orig;
    sg_controller = controller;
    return controller;
}

- (void)seekForwardBySeconds:(double)seconds {
    if (episodeSkips()) {
        skipNext();
        return;
    }
    %orig;
}

- (void)seekBackwardBySeconds:(double)seconds {
    if (episodeSkips()) {
        skipPrevious();
        return;
    }
    %orig;
}
%end

#pragma mark - the lock screen

static id sg_nextTarget, sg_previousTarget;

// Spotify answers a press of previous or next itself, when it has something to answer with for an episode.
// Asked again after a moment, one that has not moved the track is done here.
static MPRemoteCommandHandlerStatus pressed(void (*skip)(void)) {
    if (!episodeSkips()) return MPRemoteCommandHandlerStatusSuccess;
    NSString *before = playingURI();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([playingURI() isEqualToString:before]) skip();
    });
    return MPRemoteCommandHandlerStatusSuccess;
}

static void arm(void) {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    if (!sg_nextTarget) {
        sg_nextTarget = [center.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) { return pressed(skipNext); }];
        sg_previousTarget = [center.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) { return pressed(skipPrevious); }];
    }
    if (!episodeSkips()) return;
    // Through the hook below, which holds them there.
    center.skipForwardCommand.enabled = NO;
    center.skipBackwardCommand.enabled = NO;
    center.nextTrackCommand.enabled = YES;
    center.previousTrackCommand.enabled = YES;
}

%hook MPRemoteCommand
- (void)setEnabled:(BOOL)enabled {
    if (episodeSkips()) {
        MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
        if (self == center.skipForwardCommand || self == center.skipBackwardCommand) enabled = NO;
        else if (self == center.nextTrackCommand || self == center.previousTrackCommand) enabled = YES;
    }
    %orig(enabled);
}
%end

@interface SGPodcastSkipObserver : NSObject <SGPlayerStateObserver>
@end

@implementation SGPodcastSkipObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {
    arm();
}
@end

static SGPodcastSkipObserver *sg_skipObserver;

%ctor {
    %init;
    SGRequireClasses(@[@"SPTNowPlayingPlaybackControllerImplementation", @"MPRemoteCommand"]);
    sg_skipObserver = [SGPodcastSkipObserver new];
    SGAddPlayerStateObserver(sg_skipObserver);
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ arm(); });
    }];
}
