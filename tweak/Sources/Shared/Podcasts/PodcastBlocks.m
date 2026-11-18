#import "Core/SGCore.h"
#import "Podcasts.h"

NSString *const SGPodcastURI = @"uri";
NSString *const SGPodcastTitle = @"title";
NSString *const SGPodcastShow = @"show";
NSString *const SGPodcastStart = @"start";
NSString *const SGPodcastEnd = @"end";
NSString *const SGPodcastAuthor = @"author";
NSNotificationName const SGPodcastBlocksDidChangeNotification = @"spotifyglass.podcasts.blocksDidChange";
NSNotificationName const SGPodcastAuthorsDidChangeNotification = @"spotifyglass.podcasts.authorsDidChange";

NSArray<NSDictionary *> *SGPodcastBlocks(void) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyPodcastBlocks];
    return list ?: @[];
}

static void save(NSArray<NSDictionary *> *list) {
    [NSUserDefaults.standardUserDefaults setObject:list forKey:SGKeyPodcastBlocks];
    [NSNotificationCenter.defaultCenter postNotificationName:SGPodcastBlocksDidChangeNotification object:nil];
}

void SGPodcastAddBlock(NSDictionary *block) {
    save([SGPodcastBlocks() arrayByAddingObject:block]);
}

void SGPodcastReplaceBlock(NSDictionary *old, NSDictionary *replacement) {
    NSMutableArray<NSDictionary *> *list = [SGPodcastBlocks() mutableCopy];
    NSUInteger index = [list indexOfObject:old];
    if (index == NSNotFound) {
        [list addObject:replacement];
    } else {
        list[index] = replacement;
    }
    save(list);
}

void SGPodcastRemoveBlock(NSDictionary *block) {
    NSMutableArray<NSDictionary *> *list = [SGPodcastBlocks() mutableCopy];
    NSUInteger index = [list indexOfObject:block];
    if (index == NSNotFound) return;
    [list removeObjectAtIndex:index];
    save(list);
}

#pragma mark - times

// Digits, and one point in the last part for tenths of a second.
static BOOL plainNumber(NSString *part, BOOL allowPoint) {
    if (!part.length) return NO;
    BOOL point = NO, digit = NO;
    for (NSUInteger i = 0; i < part.length; i++) {
        unichar c = [part characterAtIndex:i];
        if (c >= '0' && c <= '9') { digit = YES; continue; }
        if (c == '.' && allowPoint && !point) { point = YES; continue; }
        return NO;
    }
    return digit;
}

BOOL SGPodcastParseTime(NSString *text, double *seconds) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@":"];
    if (!trimmed.length || parts.count > 3) return NO;
    double total = 0;
    for (NSUInteger i = 0; i < parts.count; i++) {
        BOOL last = i == parts.count - 1;
        if (!plainNumber(parts[i], last)) return NO;
        double value = parts[i].doubleValue;
        // 2:75 is a typo, not 3:15; the first part may run on (95:00 is a long episode).
        if (i > 0 && value >= 60) return NO;
        total = total * 60 + value;
    }
    if (seconds) *seconds = total;
    return YES;
}

NSString *SGPodcastFormatTime(double seconds) {
    NSInteger total = (NSInteger)MAX(0, floor(seconds + 0.0001));
    NSInteger hours = total / 3600, minutes = total / 60 % 60, secs = total % 60;
    if (hours) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)secs];
}

NSString *SGPodcastRangeText(NSDictionary *block) {
    double start = [block[SGPodcastStart] doubleValue], end = [block[SGPodcastEnd] doubleValue];
    return [NSString stringWithFormat:@"%@ – %@", SGPodcastFormatTime(start), end < 0 ? @"end" : SGPodcastFormatTime(end)];
}

#pragma mark - what is blocked

double SGPodcastResumePoint(NSArray<NSDictionary *> *blocks, NSString *uri, double position) {
    if (!uri.length || !isfinite(position)) return NAN;
    BOOL moved = NO;
    // One pass can land inside the next section (2:10-5:00 and 5:00-14:00), so go again until nothing covers it;
    // each pass that moves uses up at least one section, so the count bounds the loop.
    for (NSUInteger pass = 0; pass <= blocks.count; pass++) {
        BOOL again = NO;
        for (NSDictionary *block in blocks) {
            if (![block[SGPodcastURI] isEqualToString:uri]) continue;
            double start = [block[SGPodcastStart] doubleValue], end = [block[SGPodcastEnd] doubleValue];
            if (end < 0) {
                if (position >= start) return -1;
                continue;
            }
            if (position >= start && position < end) {
                position = end;
                moved = again = YES;
            }
        }
        if (!again) break;
    }
    return moved ? position : NAN;
}

#pragma mark - author names

NSArray<NSDictionary *> *SGPodcastAuthors(void) {
    return [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyPodcastAuthors] ?: @[];
}

static NSString *foldedTitle(NSString *title) {
    return [[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString] ?: @"";
}

static void saveAuthors(NSArray<NSDictionary *> *list) {
    [NSUserDefaults.standardUserDefaults setObject:list forKey:SGKeyPodcastAuthors];
    [NSNotificationCenter.defaultCenter postNotificationName:SGPodcastAuthorsDidChangeNotification object:nil];
}

void SGPodcastSetAuthor(NSDictionary *entry) {
    NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
    for (NSDictionary *existing in SGPodcastAuthors()) {
        if (![foldedTitle(existing[SGPodcastTitle]) isEqualToString:foldedTitle(entry[SGPodcastTitle])]) [list addObject:existing];
    }
    [list addObject:entry];
    saveAuthors(list);
}

void SGPodcastRemoveAuthor(NSDictionary *entry) {
    NSMutableArray<NSDictionary *> *list = [SGPodcastAuthors() mutableCopy];
    NSUInteger index = [list indexOfObject:entry];
    if (index == NSNotFound) return;
    [list removeObjectAtIndex:index];
    saveAuthors(list);
}

NSString *SGPodcastAuthorNamed(NSString *episodeTitle) {
    NSString *wanted = foldedTitle(episodeTitle);
    if (!wanted.length) return nil;
    for (NSDictionary *entry in SGPodcastAuthors()) {
        if ([foldedTitle(entry[SGPodcastTitle]) isEqualToString:wanted] && [entry[SGPodcastAuthor] length]) return entry[SGPodcastAuthor];
    }
    return nil;
}

void SGPodcastRememberAuthor(NSString *show, NSString *author) {
    NSString *key = foldedTitle(show);
    if (!key.length || !author.length) return;
    NSDictionary *known = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyPodcastShowAuthors] ?: @{};
    if ([known[key] isEqualToString:author]) return;
    NSMutableDictionary *updated = [known mutableCopy];
    updated[key] = author;
    [NSUserDefaults.standardUserDefaults setObject:updated forKey:SGKeyPodcastShowAuthors];
}

NSString *SGPodcastAuthorForShow(NSString *show) {
    NSString *key = foldedTitle(show);
    return key.length ? [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyPodcastShowAuthors][key] : nil;
}

NSString *SGPodcastCreditFor(NSString *episodeTitle, NSString *show) {
    NSString *custom = SGPodcastAuthorNamed(episodeTitle);
    if (custom.length) return custom;
    NSString *known = SGPodcastAuthorForShow(show);
    return known.length ? known : show;
}
