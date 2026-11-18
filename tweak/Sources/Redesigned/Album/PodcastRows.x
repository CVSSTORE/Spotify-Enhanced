// An episode's row drawn as a song's: the cover, the title with an E and the author under it, and the ⋯ at the
// right. On a podcast's page (the album page's template, Redesigned/Album/), on a playlist's page and on Your
// Episodes (Redesigned/Playlist/). Tapping the row plays the episode, and swiping it left saves it.
//
// Trees (2026-10-27). A show page: Element_List.CollectionViewCell > ... > Encore.ListRow
// id=Components.UI.RetrievalRowElementUI_Loaded, with EncoreConsumerMobile.View.Granular.Title / .Description /
// .Metadata / .ProgressBar. A playlist or Your Episodes: ListUXPlatform_FreeTierPlaylistImpl.ElementCollectionViewCell
// id=Playlist.ItemCell > ... > the same ListRow, with RetrievalRowElementUI9TitleView / 12SubtitleView (a label
// id=RetrievalRowElementUI.Subtitle.Label with the show) / 8BodyView. Either way, in the ListRow: a stack with
// the cover (Encore.ImageView 48x48) and the title, 64 down from the top of the cell the description and the
// progress, and under them a row of buttons, one of them the ⋯ (Components.UI.ContextMenuButton-…), then Share,
// Download, Remove (Components.UI.AddToButton) and Play (header-play-button). Nothing in a song row is below
// the first 64.
//
// So the cell is cut at 64: Spotify lays the row out at its own height inside a cell that clips, and what is
// under the cut is simply not there. The title is moved up with a transform, which Spotify's layout leaves alone
// (the ListRow's own children are not moved: it lays them out from each other's frames, and a transform on one
// sent the rest of the row off the screen). The ⋯ is drawn here and opens Spotify's menu through the row's
// accessibility action "More options", the way VoiceOver does.
//
// What goes under the title is the name set for that episode (Podcasts > Author per episode), else the
// podcast's author (Components.UI.AgentRow in a show page's header; kept for the playlists, whose rows say only
// the show), else the show. Off until Podcasts > Episodes look like songs is switched on.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Playlist/Playlist.h"
#import "Shared/Podcasts/Podcasts.h"
#import "Album.h"

static const CGFloat kRowHeight = 64;
static const CGFloat kHairline = 0.5;
static const CGFloat kSubtitleHeight = 18;
static const CGFloat kSubtitleGap = 1;
static const CGFloat kBadgeSide = 15;
// The ⋯ of an album's song row: its centre this far from the right edge.
static const CGFloat kMoreFromEdge = 33;
static const CGFloat kMoreSide = 44;
// The end of the title fades where the ⋯ begins.
static const CGFloat kFade = 40;
// A swipe this far saves the episode; the row goes no further than the other.
static const CGFloat kSwipeCommit = 72;
static const CGFloat kSwipeMax = 120;

static char kSettledKey, kMeasuredWidthKey;
static char kRowKey, kDescriptionKey, kSubLabelKey, kCoverKey, kTitleKey, kMenuKey, kPlayKey, kAddKey;
static char kShowKey, kAgentKey, kFindKey, kFindHeaderKey, kFollowerKey;
static char kSubtitleKey, kLineKey, kFadeKey, kGesturesKey, kMoreKey;

#pragma mark - the author under the title

@interface SGRPodcastSubtitle : UIView
@property (nonatomic, readonly) UILabel *show;
@end

@implementation SGRPodcastSubtitle {
    UIView *_badge;
    UILabel *_letter;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;

    // Always there, as the explicit mark of a song is: an episode has no rating of its own to read.
    _badge = [UIView new];
    _badge.layer.cornerRadius = 3;
    _badge.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_badge];
    _letter = [UILabel new];
    _letter.text = @"E";
    _letter.textAlignment = NSTextAlignmentCenter;
    _letter.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    _letter.textColor = UIColor.blackColor;
    [_badge addSubview:_letter];

    _show = [UILabel new];
    _show.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _show.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_show];
    [self sgr_colour];
    return self;
}

- (void)sgr_colour {
    _badge.backgroundColor = SGRSecondary();
    _show.textColor = SGRSecondary();
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _badge.frame = CGRectMake(0, round((bounds.size.height - kBadgeSide) / 2), kBadgeSide, kBadgeSide);
    _letter.frame = _badge.bounds;
    CGFloat lead = kBadgeSide + 6;
    _show.frame = CGRectMake(lead, 0, MAX(0, bounds.size.width - lead), bounds.size.height);
    [self sgr_colour];
}

@end

#pragma mark - what is an episode's row

static NSString *firstText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) found = text;
    });
    return found;
}

static UIView *subviewWithClassSuffix(UIView *root, NSString *suffix) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [NSStringFromClass(v.class) hasSuffix:suffix]) found = v;
    });
    return found;
}

static UIView *podcastPageOf(UIView *view) {
    return SGRAlbumPageOf(view) ?: SGRPlaylistPageOf(view);
}

static BOOL podcastActive(UIView *cell) {
    return SGFlag(SGKeyPodcastSongRows, NO) && podcastPageOf(cell);
}

// A song's row has no description or show label; an episode's has one or the other.
static UIView *episodeRowIn(UIView *cell) {
    UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
    if (!row) return nil;
    if (SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Description", &kDescriptionKey)) return row;
    return SGRFindByIdentifier(row, @"RetrievalRowElementUI.Subtitle.Label", &kSubLabelKey) ? row : nil;
}

static UIView *titleViewOf(UIView *row) {
    UIView *granular = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", &kTitleKey);
    return granular ?: subviewWithClassSuffix(row, @"RetrievalRowElementUI9TitleView");
}

// The name set for this episode, else the podcast's author, else the show.
static NSString *authorFor(UIView *page, UIView *row, UIView *title) {
    NSString *custom = SGPodcastAuthorNamed(firstText(title));
    if (custom.length) return custom;
    NSString *show = firstText(SGRFindByIdentifier(row, @"RetrievalRowElementUI.Subtitle.Label", &kSubLabelKey));
    if (!show.length) show = firstText(SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.TitleRow", &kShowKey));
    NSString *author = firstText(SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.AgentRow", &kAgentKey));
    if (author.length) {
        SGPodcastRememberAuthor(show, author);
        return author;
    }
    NSString *known = SGPodcastAuthorForShow(show);
    return known.length ? known : show;
}

#pragma mark - Spotify's own actions for the row

// What a screen reader is offered on the row: the ⋯ menu, Share, Download, and Remove when it is saved.
static UIAccessibilityCustomAction *rowAction(UIView *row, BOOL (^match)(NSString *name)) {
    for (UIView *v = row; v; v = v.superview) {
        for (UIAccessibilityCustomAction *action in v.accessibilityCustomActions) {
            if (match(action.name)) return action;
        }
        if ([v isKindOfClass:UICollectionViewCell.class]) break;
    }
    return nil;
}

static BOOL performAction(UIAccessibilityCustomAction *action) {
    if (action.actionHandler) return action.actionHandler(action);
    if (action.target && action.selector && [action.target respondsToSelector:action.selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [action.target performSelector:action.selector withObject:action];
#pragma clang diagnostic pop
        return YES;
    }
    return NO;
}

static void openMenu(UIView *row) {
    UIAccessibilityCustomAction *action = rowAction(row, ^BOOL(NSString *name) { return [name hasPrefix:@"More options"]; });
    if (action && performAction(action)) return;
    UIView *menu = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton*", &kMenuKey);
    if (menu) SGRActivate(menu);
}

static BOOL isSaveName(NSString *name) {
    return [name hasPrefix:@"Remove"] || [name hasPrefix:@"Save"] || [name hasPrefix:@"Add to Your"];
}

static BOOL canSave(UIView *row) {
    return SGRFindByIdentifier(row, @"Components.UI.AddToButton", &kAddKey) || rowAction(row, ^BOOL(NSString *name) { return isSaveName(name); });
}

static void save(UIView *row) {
    UIView *button = SGRFindByIdentifier(row, @"Components.UI.AddToButton", &kAddKey);
    if (button) {
        SGRActivate(button);
        return;
    }
    UIAccessibilityCustomAction *action = rowAction(row, ^BOOL(NSString *name) { return isSaveName(name); });
    if (action) performAction(action);
}

@interface SGRPodcastMore : UIControl
@property (nonatomic, weak) UIView *row;
@end

@implementation SGRPodcastMore {
    UIImageView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:config]];
    _glyph.contentMode = UIViewContentModeCenter;
    _glyph.userInteractionEnabled = NO;
    _glyph.tintColor = SGRSecondary();
    [self addSubview:_glyph];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"More options";
    [self addTarget:self action:@selector(sgr_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glyph.frame = self.bounds;
    _glyph.tintColor = SGRSecondary();
}

- (void)sgr_tap {
    UIView *row = self.row;
    if (row) openMenu(row);
}

@end

#pragma mark - tap and swipe

@interface SGRPodcastGestures : NSObject <UIGestureRecognizerDelegate>
- (instancetype)initWithCell:(UICollectionViewCell *)cell;
- (void)linkSelection;
- (void)teardown;
@end

@implementation SGRPodcastGestures {
    __weak UICollectionViewCell *_cell;
    UITapGestureRecognizer *_tap;
    UIPanGestureRecognizer *_pan;
    UIView *_backdrop;
    UIImageView *_glyph;
    BOOL _linked;
}

- (instancetype)initWithCell:(UICollectionViewCell *)cell {
    if (!(self = [super init])) return nil;
    _cell = cell;
    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_tapped)];
    _tap.delegate = self;
    [cell addGestureRecognizer:_tap];
    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_panned:)];
    _pan.delegate = self;
    [cell addGestureRecognizer:_pan];
    return self;
}

// The list picks the row a tap lands on by itself; it is told to wait for this tap to fail first.
- (void)linkSelection {
    if (_linked) return;
    UIView *list = _cell.superview;
    while (list && ![list isKindOfClass:UICollectionView.class]) list = list.superview;
    if (!list) return;
    for (UIGestureRecognizer *other in list.gestureRecognizers) {
        if ([other isKindOfClass:UITapGestureRecognizer.class] && other != _tap) [other requireGestureRecognizerToFail:_tap];
    }
    _linked = YES;
}

- (void)teardown {
    [self sgr_shift:0];
    [_backdrop removeFromSuperview];
    [_cell removeGestureRecognizer:_tap];
    [_cell removeGestureRecognizer:_pan];
}

- (UIView *)sgr_row {
    return _cell ? episodeRowIn(_cell) : nil;
}

- (UIView *)sgr_playButton {
    return SGRFindByIdentifier([self sgr_row], @"header-play-button", &kPlayKey);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (!_cell || !podcastActive(_cell)) return NO;
    UIView *row = [self sgr_row];
    if (!row) return NO;
    // The ⋯ is its own control, which takes its own touch.
    if ([touch.view isKindOfClass:SGRPodcastMore.class]) return NO;
    return recognizer == _tap ? [self sgr_playButton] != nil : canSave(row);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != _pan) return YES;
    CGPoint velocity = [_pan velocityInView:_cell];
    return velocity.x < 0 && fabs(velocity.x) > fabs(velocity.y) * 1.5;
}

- (void)sgr_tapped {
    UIView *play = [self sgr_playButton];
    if (!play) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    SGRActivate(play);
}

- (void)sgr_ensureBackdrop {
    if (!_backdrop) {
        _backdrop = [UIView new];
        _backdrop.backgroundColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
        _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]];
        _glyph.tintColor = UIColor.blackColor;
        _glyph.contentMode = UIViewContentModeCenter;
        [_backdrop addSubview:_glyph];
    }
    if (_backdrop.superview != _cell) [_cell insertSubview:_backdrop atIndex:0];
    _backdrop.hidden = NO;
    _backdrop.frame = _cell.bounds;
    _glyph.frame = CGRectMake(_cell.bounds.size.width - 64, 0, 56, _cell.bounds.size.height);
}

// What moves is the row's own content and the author put over it.
- (void)sgr_shift:(CGFloat)x {
    UICollectionViewCell *cell = _cell;
    if (!cell) return;
    CGAffineTransform t = x == 0 ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(x, 0);
    cell.contentView.transform = t;
    ((UIView *)objc_getAssociatedObject(cell, &kSubtitleKey)).transform = t;
    ((UIView *)objc_getAssociatedObject(cell, &kMoreKey)).transform = t;
    ((CALayer *)objc_getAssociatedObject(cell, &kLineKey)).hidden = x != 0;
    _glyph.alpha = MIN(1, fabs(x) / kSwipeCommit);
}

- (void)sgr_panned:(UIPanGestureRecognizer *)pan {
    CGFloat dx = MIN(0, [pan translationInView:_cell].x);
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            [self sgr_ensureBackdrop];
            [self sgr_shift:MAX(dx, -kSwipeMax)];
            break;
        default: {
            BOOL commit = pan.state == UIGestureRecognizerStateEnded && dx <= -kSwipeCommit;
            [UIView animateWithDuration:0.2 animations:^{ [self sgr_shift:0]; } completion:^(BOOL finished) {
                self->_backdrop.hidden = YES;
            }];
            UIView *row = commit ? [self sgr_row] : nil;
            if (row) {
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
                save(row);
            }
        }
    }
}

@end

#pragma mark - the cut

static void settle(UICollectionViewCell *cell, CGFloat natural) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, @(natural), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    // Bounds and centre, which hold with a transform on it; the frame does not.
    CGRect bounds = CGRectMake(0, 0, cell.bounds.size.width, natural);
    CGPoint centre = CGPointMake(bounds.size.width / 2, natural / 2);
    if (!CGRectEqualToRect(content.bounds, bounds)) content.bounds = bounds;
    if (!CGPointEqualToPoint(content.center, centre)) content.center = centre;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
}

static void unsettle(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    SGRPodcastGestures *gestures = objc_getAssociatedObject(cell, &kGesturesKey);
    [gestures teardown];
    objc_setAssociatedObject(cell, &kGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kSettledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kMeasuredWidthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.transform = CGAffineTransformIdentity;
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    cell.clipsToBounds = NO;

    [(UIView *)objc_getAssociatedObject(cell, &kSubtitleKey) removeFromSuperview];
    objc_setAssociatedObject(cell, &kSubtitleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [(UIView *)objc_getAssociatedObject(cell, &kMoreKey) removeFromSuperview];
    objc_setAssociatedObject(cell, &kMoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [(CALayer *)objc_getAssociatedObject(cell, &kLineKey) removeFromSuperlayer];
    UIView *row = SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
    if (row) {
        titleViewOf(row).transform = CGAffineTransformIdentity;
        titleViewOf(row).layer.mask = nil;
        subviewWithClassSuffix(row, @"RetrievalRowElementUI12SubtitleView").alpha = 1;
    }
    objc_setAssociatedObject(cell, &kFadeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - the row

static void restyle(UICollectionViewCell *cell, UIView *row) {
    UIView *page = podcastPageOf(cell);
    UIView *cover = SGRFindByIdentifier(row, @"Encore.ImageView", &kCoverKey);
    UIView *title = titleViewOf(row);
    if (!page || !cover || !title) return;

    CGFloat width = cell.bounds.size.width;
    CGRect coverFrame = [cell convertRect:cover.bounds fromView:cover];
    // Measured where Spotify put it, not where it has been moved to.
    title.transform = CGAffineTransformIdentity;
    CGRect titleFrame = [cell convertRect:title.bounds fromView:title];
    if (coverFrame.size.width < 1 || titleFrame.size.width < 1) return;

    // A playlist's row has its own show under the title; the author goes there instead.
    UIView *ownSubtitle = subviewWithClassSuffix(row, @"RetrievalRowElementUI12SubtitleView");
    if (ownSubtitle.alpha != 0) ownSubtitle.alpha = 0;

    // The title and the author are a pair, centred on the cover.
    CGFloat pair = titleFrame.size.height + kSubtitleGap + kSubtitleHeight;
    CGFloat top = round(CGRectGetMidY(coverFrame) - pair / 2);
    title.transform = CGAffineTransformMakeTranslation(0, top - titleFrame.origin.y);

    // A long title fades out before the ⋯ rather than running under it.
    CAGradientLayer *fade = objc_getAssociatedObject(cell, &kFadeKey);
    if (!fade) {
        fade = [CAGradientLayer layer];
        fade.startPoint = CGPointMake(0, 0.5);
        fade.endPoint = CGPointMake(1, 0.5);
        fade.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
        objc_setAssociatedObject(cell, &kFadeKey, fade, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat span = MAX(1, title.bounds.size.width);
    CGFloat reach = width - kMoreFromEdge - kMoreSide / 2 - titleFrame.origin.x;
    CGFloat end = MIN(1, MAX(0.2, reach / span)), start = MAX(0, end - kFade / span);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fade.locations = @[@0, @(start), @(end)];
    fade.frame = title.bounds;
    [CATransaction commit];
    if (title.layer.mask != fade) title.layer.mask = fade;

    SGRPodcastSubtitle *subtitle = objc_getAssociatedObject(cell, &kSubtitleKey);
    if (!subtitle) {
        subtitle = [[SGRPodcastSubtitle alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(cell, &kSubtitleKey, subtitle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (subtitle.superview != cell) [cell addSubview:subtitle];
    subtitle.frame = CGRectMake(titleFrame.origin.x, top + titleFrame.size.height + kSubtitleGap, MAX(0, reach - 8), kSubtitleHeight);
    NSString *name = authorFor(page, row, title);
    if (name && ![subtitle.show.text isEqualToString:name]) subtitle.show.text = name;
    [cell bringSubviewToFront:subtitle];

    // The ⋯, where a song's is.
    SGRPodcastMore *more = objc_getAssociatedObject(cell, &kMoreKey);
    if (!more) {
        more = [[SGRPodcastMore alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(cell, &kMoreKey, more, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    more.row = row;
    if (more.superview != cell) [cell addSubview:more];
    more.frame = CGRectMake(width - kMoreFromEdge - kMoreSide / 2, round(CGRectGetMidY(coverFrame) - kMoreSide / 2), kMoreSide, kMoreSide);
    UIAccessibilityCustomAction *menuAction = rowAction(row, ^BOOL(NSString *name) { return [name hasPrefix:@"More options"]; });
    if (menuAction.name.length && ![more.accessibilityLabel isEqualToString:menuAction.name]) more.accessibilityLabel = menuAction.name;
    [cell bringSubviewToFront:more];

    // The line under the text, as the album's rows have it; the row's own is under the cut.
    CALayer *line = objc_getAssociatedObject(cell, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.zPosition = 1;
        objc_setAssociatedObject(cell, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    line.backgroundColor = SGRHairline().CGColor;
    if (line.superlayer != cell.layer) [cell.layer addSublayer:line];
    CGRect lineFrame = CGRectMake(SGRSideMargin, kRowHeight - kHairline, MAX(0, width - 2 * SGRSideMargin), kHairline);
    if (!CGRectEqualToRect(line.frame, lineFrame)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        line.frame = lineFrame;
        [CATransaction commit];
    }

    SGRPodcastGestures *gestures = objc_getAssociatedObject(cell, &kGesturesKey);
    if (!gestures) {
        gestures = [[SGRPodcastGestures alloc] initWithCell:cell];
        objc_setAssociatedObject(cell, &kGesturesKey, gestures, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [gestures linkSelection];
}

// Measured once per width: asked again with the content pinned, Spotify answers differently each time.
static UICollectionViewLayoutAttributes *settledAttributes(UICollectionViewCell *cell, UICollectionViewLayoutAttributes *attributes) {
    NSNumber *settled = objc_getAssociatedObject(cell, &kSettledKey);
    NSNumber *measured = objc_getAssociatedObject(cell, &kMeasuredWidthKey);
    if (!settled || !measured || fabs(measured.doubleValue - attributes.size.width) >= 0.5) return nil;
    if (!podcastActive(cell) || !episodeRowIn(cell)) return nil;
    UICollectionViewLayoutAttributes *again = [attributes copy];
    again.size = CGSizeMake(attributes.size.width, kRowHeight);
    return again;
}

static UICollectionViewLayoutAttributes *cutAttributes(UICollectionViewCell *cell, UICollectionViewLayoutAttributes *result, UICollectionViewLayoutAttributes *attributes) {
    BOOL settled = objc_getAssociatedObject(cell, &kSettledKey) != nil;
    if (!podcastActive(cell) || !episodeRowIn(cell)) {
        // Cells are reused across kinds, and one cut before can hold a song or a heading now.
        if (settled) unsettle(cell);
        return result;
    }
    settle(cell, MAX(1, result.size.height));
    result.size = CGSizeMake(result.size.width, kRowHeight);
    objc_setAssociatedObject(cell, &kMeasuredWidthKey, @(attributes.size.width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign podcast: an episode's row cut to a song's height"); });
    return result;
}

// The cell's own passes size the content to the cell again.
static void layoutCell(UICollectionViewCell *cell) {
    NSNumber *settled = objc_getAssociatedObject(cell, &kSettledKey);
    if (!settled) return;
    UIView *row = episodeRowIn(cell);
    // Switched off while it was cut.
    if (!row || !podcastActive(cell)) {
        unsettle(cell);
        return;
    }
    settle(cell, settled.doubleValue);
    restyle(cell, row);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *again = settledAttributes((UICollectionViewCell *)self, attributes);
    if (again) return again;
    return cutAttributes((UICollectionViewCell *)self, %orig, attributes);
}

- (void)layoutSubviews {
    %orig;
    layoutCell((UICollectionViewCell *)self);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kSettledKey)) unsettle((UICollectionViewCell *)self);
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *again = settledAttributes((UICollectionViewCell *)self, attributes);
    if (again) return again;
    return cutAttributes((UICollectionViewCell *)self, %orig, attributes);
}

- (void)layoutSubviews {
    %orig;
    layoutCell((UICollectionViewCell *)self);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kSettledKey)) unsettle((UICollectionViewCell *)self);
}
%end

#pragma mark - the sort and filter heading

// "Newest • All Episodes" is Spotify's own strip across the list, painted black; the page's field shows
// through everywhere else. Spotify's paint is not one that could be found in the tree (the strip stayed black
// with every background under it cleared), so the strip is blended in with the screen filter instead: black
// adds nothing to what is behind it, and the white of the words and the glyph stays. Done when the view comes
// to the screen and when it is given something to hold, not only when it is laid out, which is why it showed
// only after the button was pressed.
static BOOL isPodcastPage(UIView *page) {
    return page && SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.FindRow", &kFindKey);
}

static void soften(UIView *view) {
    UIView *page = SGRAlbumPageOf(view);
    if (!isPodcastPage(page)) return;
    if (view.layer.compositingFilter == nil) view.layer.compositingFilter = @"screenBlendMode";
    if (view.backgroundColor) view.backgroundColor = UIColor.clearColor;
    SGStripBackgrounds(view);
}

%hook _TtC12Element_List21SupplementaryItemView
- (void)layoutSubviews {
    %orig;
    soften((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) soften((UIView *)self);
}

- (void)didAddSubview:(UIView *)subview {
    %orig;
    soften((UIView *)self);
}
%end

#pragma mark - the search field

// "Find in this show" is pinned under the navigation bar. It sits instead in the gap between the show's rating
// and its tabs (in the header, 258 down from its top) and scrolls up with the page until it reaches the place
// it was pinned at, and stays there.
static const CGFloat kFindInHeader = 258;

@interface SGRFindFollower : NSObject
- (instancetype)initWithPage:(UIView *)page find:(UIView *)find header:(UIView *)header;
@property (nonatomic, weak, readonly) UIView *find;
@end

@implementation SGRFindFollower {
    __weak UIView *_page;
    __weak UIView *_header;
    CADisplayLink *_link;
}

- (instancetype)initWithPage:(UIView *)page find:(UIView *)find header:(UIView *)header {
    if (!(self = [super init])) return nil;
    _page = page;
    _find = find;
    _header = header;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(sgr_tick)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

// Not a scroll observer: a scroll view tells nobody its offset changed except by key-value observing, and an
// observer left on a view that goes first is an exception.
- (void)sgr_tick {
    UIView *page = _page, *find = _find, *header = _header;
    if (!page || !find || !header) {
        [_link invalidate];
        _link = nil;
        return;
    }
    if (!page.window) return;
    // Where Spotify put it, whatever the transform has moved it to since.
    CGFloat pinned = find.center.y - find.bounds.size.height / 2;
    CGFloat resting = [header convertPoint:CGPointZero toView:page].y + kFindInHeader;
    CGFloat shift = MAX(pinned, resting) - pinned;
    if (fabs(find.transform.ty - shift) > 0.01) find.transform = CGAffineTransformMakeTranslation(0, shift);
}

@end

static void placeFind(UIView *page) {
    UIView *find = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.FindRow", &kFindKey);
    UIView *header = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader", &kFindHeaderKey);
    if (!find || !header) return;
    SGRFindFollower *follower = objc_getAssociatedObject(page, &kFollowerKey);
    if (follower.find == find) return;
    objc_setAssociatedObject(page, &kFollowerKey, [[SGRFindFollower alloc] initWithPage:page find:find header:header], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGLog(@"redesign podcast: the search field moved down into the header");
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    placeFind((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell",
        @"_TtC12Element_List21SupplementaryItemView",
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
    ]);
}
