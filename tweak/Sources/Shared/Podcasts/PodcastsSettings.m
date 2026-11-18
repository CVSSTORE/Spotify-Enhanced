#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Podcasts.h"

static NSString *const kTimesNote = @"Times look like 2:10 or 1:02:10. Leave the end empty to block to the end of the episode. Tap a section to change it, swipe to remove it.";

typedef NS_ENUM(NSInteger, SGPodcastBlocksSection) {
    SGPodcastBlocksSectionAdd,
    SGPodcastBlocksSectionList,
    SGPodcastBlocksSectionCount,
};

@interface SGPodcastBlocksPageController : SGPage
@end

@implementation SGPodcastBlocksPageController {
    NSArray<NSDictionary *> *_blocks;   // by episode, in the order each first appears, then by start
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Blocked sections";
    _blocks = [self sorted];
    return self;
}

- (NSArray<NSDictionary *> *)sorted {
    NSArray<NSDictionary *> *all = SGPodcastBlocks();
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSDictionary *block in all) {
        if (![order containsObject:block[SGPodcastURI]]) [order addObject:block[SGPodcastURI]];
    }
    return [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger left = [order indexOfObject:a[SGPodcastURI]], right = [order indexOfObject:b[SGPodcastURI]];
        if (left != right) return left < right ? NSOrderedAscending : NSOrderedDescending;
        return [a[SGPodcastStart] compare:b[SGPodcastStart]];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)reload {
    _blocks = [self sorted];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGPodcastBlocksSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == SGPodcastBlocksSectionList ? MAX((NSInteger)_blocks.count, 1) : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == SGPodcastBlocksSectionList ? SGSectionHeader(table, @"Blocked") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGPodcastBlocksSectionList ? SGSectionHeaderHeight : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return section == SGPodcastBlocksSectionList ? SGSectionFooter(table, kTimesNote) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return section == SGPodcastBlocksSectionList ? SGSectionFooterHeight(table, kTimesNote) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"podcastBlock");
    if (path.section == SGPodcastBlocksSectionAdd) {
        SGFillCell(cell, @"Block part of what's playing…", nil, nil, @"scissors");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (!_blocks.count) {
        SGFillCell(cell, @"Nothing blocked yet", nil, SGGrey(), nil);
        return cell;
    }
    NSDictionary *block = _blocks[(NSUInteger)path.row];
    NSString *show = block[SGPodcastShow];
    NSString *range = SGPodcastRangeText(block);
    SGFillCell(cell, block[SGPodcastTitle], show.length ? [NSString stringWithFormat:@"%@ · %@", range, show] : range, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGPodcastBlocksSectionList && _blocks.count > 0;
}

- (NSString *)tableView:(UITableView *)table titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path {
    return @"Remove";
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    SGPodcastRemoveBlock(_blocks[(NSUInteger)path.row]);
    [self reload];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGPodcastBlocksSectionAdd) {
        NSDictionary *episode = SGPodcastPlayingEpisode();
        if (!episode) {
            [self say:@"No episode playing" message:@"Play the podcast episode first, then come back here to block a part of it."];
            return;
        }
        [self edit:nil episode:episode];
    } else if (_blocks.count) {
        NSDictionary *block = _blocks[(NSUInteger)path.row];
        [self edit:block episode:block];
    }
}

- (void)say:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// A new section of the episode playing now, or `existing` changed; `episode` names the episode either way.
- (void)edit:(NSDictionary *)existing episode:(NSDictionary *)episode {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:existing ? @"Change section" : @"Block a section"
                                                                  message:episode[SGPodcastTitle]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    double now = SGPodcastPlayingPosition();
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = !existing && now >= 0 ? [NSString stringWithFormat:@"From, e.g. 2:10 (now %@)", SGPodcastFormatTime(now)] : @"From, e.g. 2:10";
        field.text = existing ? SGPodcastFormatTime([existing[SGPodcastStart] doubleValue]) : nil;
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"To, e.g. 14:00 (empty: the end)";
        double end = [existing[SGPodcastEnd] doubleValue];
        field.text = existing && end >= 0 ? SGPodcastFormatTime(end) : nil;
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak SGPodcastBlocksPageController *weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weak save:existing episode:episode from:alert.textFields[0].text to:alert.textFields[1].text];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)save:(NSDictionary *)existing episode:(NSDictionary *)episode from:(NSString *)fromText to:(NSString *)toText {
    double start = 0, end = -1;
    if (!SGPodcastParseTime(fromText, &start)) {
        [self say:@"Check the start" message:@"Write the start as minutes and seconds, like 2:10, or as hours too, like 1:02:10."];
        return;
    }
    NSString *to = [[toText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (to.length && ![to isEqualToString:@"end"]) {
        if (!SGPodcastParseTime(to, &end)) {
            [self say:@"Check the end" message:@"Write the end like 14:00, or leave it empty to block to the end of the episode."];
            return;
        }
        if (end <= start) {
            [self say:@"The end is before the start" message:@"The section has to end after it begins."];
            return;
        }
    }
    NSDictionary *block = @{
        SGPodcastURI: episode[SGPodcastURI],
        SGPodcastTitle: episode[SGPodcastTitle] ?: @"",
        SGPodcastShow: episode[SGPodcastShow] ?: @"",
        SGPodcastStart: @(start),
        SGPodcastEnd: @(end),
    };
    if (existing) SGPodcastReplaceBlock(existing, block);
    else SGPodcastAddBlock(block);
    // Someone who blocks a part of an episode wants it skipped, so the first one switches the blocker on.
    if (!SGFlag(SGKeyPodcastBlocker, NO)) SGSetEnabled(SGKeyPodcastBlocker, YES);
    [self reload];
}

@end


#pragma mark - author names

static NSString *const kAuthorsNote = @"The name shows under the episode instead of its podcast's author, wherever episodes look like songs. Tap a name to change it, swipe to remove it.";

typedef NS_ENUM(NSInteger, SGPodcastAuthorsSection) {
    SGPodcastAuthorsSectionAdd,
    SGPodcastAuthorsSectionList,
    SGPodcastAuthorsSectionCount,
};

@interface SGPodcastAuthorsPageController : SGPage
@end

@implementation SGPodcastAuthorsPageController {
    NSArray<NSDictionary *> *_entries;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Author per episode";
    _entries = SGPodcastAuthors();
    return self;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)reload {
    _entries = SGPodcastAuthors();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGPodcastAuthorsSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == SGPodcastAuthorsSectionList ? MAX((NSInteger)_entries.count, 1) : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == SGPodcastAuthorsSectionList ? SGSectionHeader(table, @"Names") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGPodcastAuthorsSectionList ? SGSectionHeaderHeight : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return section == SGPodcastAuthorsSectionList ? SGSectionFooter(table, kAuthorsNote) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return section == SGPodcastAuthorsSectionList ? SGSectionFooterHeight(table, kAuthorsNote) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"podcastAuthor");
    if (path.section == SGPodcastAuthorsSectionAdd) {
        SGFillCell(cell, @"Name the episode playing now…", nil, nil, @"person.text.rectangle");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (!_entries.count) {
        SGFillCell(cell, @"No names set yet", nil, SGGrey(), nil);
        return cell;
    }
    NSDictionary *entry = _entries[(NSUInteger)path.row];
    SGFillCell(cell, entry[SGPodcastTitle], entry[SGPodcastAuthor], nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGPodcastAuthorsSectionList && _entries.count > 0;
}

- (NSString *)tableView:(UITableView *)table titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)path {
    return @"Remove";
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    SGPodcastRemoveAuthor(_entries[(NSUInteger)path.row]);
    [self reload];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGPodcastAuthorsSectionAdd) {
        NSDictionary *episode = SGPodcastPlayingEpisode();
        if (!episode) {
            [self say:@"No episode playing" message:@"Play the podcast episode first, then come back here to name it."];
            return;
        }
        [self editTitle:episode[SGPodcastTitle] current:SGPodcastAuthorNamed(episode[SGPodcastTitle]) ?: episode[SGPodcastShow]];
    } else if (_entries.count) {
        NSDictionary *entry = _entries[(NSUInteger)path.row];
        [self editTitle:entry[SGPodcastTitle] current:entry[SGPodcastAuthor]];
    }
}

- (void)say:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editTitle:(NSString *)title current:(NSString *)current {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Author name" message:title preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Any name";
        field.text = current;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak SGPodcastAuthorsPageController *weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) return;
        SGPodcastSetAuthor(@{SGPodcastTitle: title ?: @"", SGPodcastAuthor: name});
        [weak reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGPodcastAuthorsPage(void) {
    return [SGPodcastAuthorsPageController new];
}

UIViewController *SGPodcastBlocksPage(void) {
    return [SGPodcastBlocksPageController new];
}

NSString *SGPodcastsSummary(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (SGFlag(SGKeyPodcastStartAtZero, NO)) [parts addObject:@"From 0:00"];
    NSUInteger count = SGPodcastBlocks().count;
    if (SGFlag(SGKeyPodcastBlocker, NO) && count) [parts addObject:[NSString stringWithFormat:@"%lu blocked", (unsigned long)count]];
    return parts.count ? [parts componentsJoinedByString:@" · "] : @"Off";
}

UIViewController *SGPodcastsSettingsPage(void) {
    SGModRow *startAtZero = SGOptionRow(@"Always start at 0:00",
        @"A podcast episode begins at the start, not where you left off", SGKeyPodcastStartAtZero);
    SGModRow *restart = SGOptionRow(@"Restart when you press play",
        @"Pause, then play: the episode goes back to 0:00", SGKeyPodcastRestartOnPlay);

    SGModRow *blocker = SGOptionRow(@"Skip blocked sections",
        @"Jump over the parts of an episode you blocked", SGKeyPodcastBlocker);
    SGModRow *blocks = SGPageRow(@"Blocked sections", ^UIViewController *{ return SGPodcastBlocksPage(); });
    blocks.value = ^NSString *{ return @(SGPodcastBlocks().count).stringValue; };
    blocks.refreshOn = SGPodcastBlocksDidChangeNotification;

    SGModRow *authors = SGPageRow(@"Author per episode", ^UIViewController *{ return SGPodcastAuthorsPage(); });
    authors.value = ^NSString *{ return @(SGPodcastAuthors().count).stringValue; };
    authors.refreshOn = SGPodcastAuthorsDidChangeNotification;

    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"Show page", @[
            SGWithSymbol(SGOptionRow(@"Episodes look like songs", @"Changes podcast episodes to the song format", SGKeyPodcastSongRows), @"music.note.list"),
            SGWithSymbol(authors, @"person.text.rectangle"),
        ], @"Redesigned look only. Under an episode goes the podcast's author, or the name you set for that episode."),
        SGNotedSection(@"Skip", @[
            SGWithSymbol(SGSwitchRow(@"Skip like songs", @"Next and previous in place of ±15 seconds", SGKeyPodcastSkipTracks), @"forward.fill"),
        ], @"In the player and on the lock screen. Double-tap and swipe zones that seek still move by seconds only on songs."),
        SGNotedSection(@"Start", @[
            SGWithSymbol(startAtZero, @"backward.end.alt"),
            SGWithSymbol(restart, @"arrow.counterclockwise"),
        ], @"Restart on play also resets an episode you paused to come back to, so leave it off if you only want new episodes to begin at 0:00."),
        SGNotedSection(@"Blocker", @[
            SGWithSymbol(blocker, @"forward.end"),
            SGWithSymbol(blocks, @"scissors"),
        ], @"Block 2:10–14:00 of an episode and it plays 0:00 to 2:10, then carries on at 14:00. Open the episode, then Blocked sections › Block part of what's playing."),
    ];
    return [[SGModPage alloc] initWithTitle:@"Podcasts" intro:nil sections:sections footer:nil];
}
