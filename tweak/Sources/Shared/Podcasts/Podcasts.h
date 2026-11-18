#import <UIKit/UIKit.h>

// Podcasts: episodes that start at 0:00, and sections of an episode that are skipped.
#define SGKeyPodcastStartAtZero @"spotifyglass.podcasts.startAtZero"       // a new episode starts at 0:00, not where it was left
#define SGKeyPodcastRestartOnPlay @"spotifyglass.podcasts.restartOnPlay"   // pause, then play: back to 0:00
#define SGKeyPodcastBlocker @"spotifyglass.podcasts.blocker"               // blocked sections are skipped
#define SGKeyPodcastBlocks @"spotifyglass.podcasts.blocks"
// Redesigned UI: a show page's episode rows drawn as song rows (Redesigned/Album/PodcastRows.x); off until switched on.
#define SGKeyPodcastSongRows @"spotifyglass.podcasts.songRows"
#define SGKeyPodcastAuthors @"spotifyglass.podcasts.authors"
#define SGKeyPodcastSkipTracks @"spotifyglass.podcasts.skipTracks"   // an episode's ±15 s buttons skip tracks; on until switched off
#define SGKeyPodcastShowAuthors @"spotifyglass.podcasts.showAuthors"   // show name to the author its page showed

// One blocked section is a dictionary of these keys.
extern NSString *const SGPodcastURI;     // NSString, spotify:episode:…
extern NSString *const SGPodcastTitle;   // NSString, the episode
extern NSString *const SGPodcastShow;    // NSString, the show; may be empty
extern NSString *const SGPodcastStart;   // NSNumber, seconds
extern NSString *const SGPodcastEnd;     // NSNumber, seconds; negative for "to the end of the episode"

extern NSString *const SGPodcastAuthor;  // NSString, the name shown under an episode in place of its podcast's author
extern NSNotificationName const SGPodcastBlocksDidChangeNotification;
extern NSNotificationName const SGPodcastAuthorsDidChangeNotification;

NSArray<NSDictionary *> *SGPodcastBlocks(void);
void SGPodcastAddBlock(NSDictionary *block);
void SGPodcastReplaceBlock(NSDictionary *old, NSDictionary *replacement);
void SGPodcastRemoveBlock(NSDictionary *block);

// Names that replace the author shown under one episode (SGPodcastTitle and SGPodcastAuthor, and the show for the list).
NSArray<NSDictionary *> *SGPodcastAuthors(void);
void SGPodcastSetAuthor(NSDictionary *entry);        // one name an episode title; setting it again replaces
void SGPodcastRemoveAuthor(NSDictionary *entry);
NSString *SGPodcastAuthorNamed(NSString *episodeTitle);   // nil when none is set
// A show's page says who makes it; a playlist's row says only the show. What a page said is kept for the rows.
void SGPodcastRememberAuthor(NSString *show, NSString *author);
NSString *SGPodcastAuthorForShow(NSString *show);        // nil when its page has not been seen
// Who an episode is credited to, in the stats: the name set for it, else its show's author, else the show.
NSString *SGPodcastCreditFor(NSString *episodeTitle, NSString *show);

// "2:10", "1:02:10" or plain seconds. NO for anything else, empty included.
BOOL SGPodcastParseTime(NSString *text, double *seconds);
NSString *SGPodcastFormatTime(double seconds);   // 2:10, 1:02:10
NSString *SGPodcastRangeText(NSDictionary *block);   // "2:10 – 14:00", "40:00 – end"

// Where playback has to go if `position` sits inside a blocked section of the episode: the end of the run
// of sections that covers it (overlapping and touching ones chain), negative for the end of the episode,
// NAN when the position is not blocked.
double SGPodcastResumePoint(NSArray<NSDictionary *> *blocks, NSString *uri, double position);

// PodcastPlayback.x: the episode playing now as SGPodcastURI, SGPodcastTitle and SGPodcastShow; nil when
// what plays is not an episode. SGPodcastPlayingPosition is negative when unknown.
NSDictionary *SGPodcastPlayingEpisode(void);
double SGPodcastPlayingPosition(void);

UIViewController *SGPodcastsSettingsPage(void);   // the Podcasts page
UIViewController *SGPodcastBlocksPage(void);      // its list of blocked sections
UIViewController *SGPodcastAuthorsPage(void);     // the names that replace an episode's author
NSString *SGPodcastsSummary(void);                // what the Mod Settings row shows beside its chevron
