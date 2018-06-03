//
//  AgendaViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/18/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "Itsycal.h"
#import "AgendaViewController.h"
#import "EventCenter.h"
#import "MoButton.h"
#import "MoVFLHelper.h"
#import "Themer.h"

static NSString *kColumnIdentifier    = @"Column";
static NSString *kDateCellIdentifier  = @"DateCell";
static NSString *kEventCellIdentifier = @"EventCell";

@interface ThemedScroller : NSScroller
@end

@interface AgendaRowView : NSTableRowView
@property (nonatomic) BOOL isHovered;
@end

@interface AgendaDateCell : NSView
@property (nonatomic) NSTextField *dayTextField;
@property (nonatomic) NSTextField *DOWTextField;
@property (nonatomic, weak) NSDate *date;
@property (nonatomic, readonly) CGFloat height;
@end

@interface AgendaEventCell : NSView
@property (nonatomic) NSGridView *grid;
@property (nonatomic) NSTextField *titleTextField;
@property (nonatomic) NSTextField *locationTextField;
@property (nonatomic) NSTextField *durationTextField;
@property (nonatomic, weak) EventInfo *eventInfo;
@property (nonatomic, readonly) CGFloat height;
@property (nonatomic) BOOL dim;
@end

#pragma mark -
#pragma mark AgendaViewController

// =========================================================================
// AgendaViewController
// =========================================================================

@implementation AgendaViewController

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;

    // Calendars table view context menu
    NSMenu *contextMenu = [NSMenu new];
    contextMenu.delegate = self;

    // Calendars table view
    _tv = [MoTableView new];
    _tv.menu = contextMenu;
    _tv.headerView = nil;
    _tv.allowsColumnResizing = NO;
    _tv.intercellSpacing = NSMakeSize(0, 0);
    _tv.backgroundColor = [[Themer shared] mainBackgroundColor];
    _tv.floatsGroupRows = YES;
    _tv.refusesFirstResponder = YES;
    _tv.dataSource = self;
    _tv.delegate = self;
    [_tv addTableColumn:[[NSTableColumn alloc] initWithIdentifier:kColumnIdentifier]];
    
    // Calendars enclosing scrollview
    NSScrollView *tvContainer = [NSScrollView new];
    tvContainer.translatesAutoresizingMaskIntoConstraints = NO;
    tvContainer.drawsBackground = NO;
    tvContainer.hasVerticalScroller = YES;
    tvContainer.documentView = _tv;
    tvContainer.verticalScroller = [ThemedScroller new];
    
    [v addSubview:tvContainer];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[tv]|" options:0 metrics:nil views:@{@"tv": tvContainer}]];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[tv]|" options:0 metrics:nil views:@{@"tv": tvContainer}]];
    
    self.view = v;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    REGISTER_FOR_THEME_CHANGE;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [self reloadData];
}

- (void)viewDidLayout
{
    // Calculate height of view based on _tv row heights.
    // We set the view's height using preferredContentSize.
    NSInteger rows = [_tv numberOfRows];
    CGFloat height = 0;
    for (NSInteger row = 0; row < rows; ++row) {
        height += [self tableView:_tv heightOfRow:row];
    }
    // Limit view height to a max of 500.
    height = MIN(height, 500);
    // If height is 0, we make it 0.001 which is effectively the
    // same dimension. When preferredContentSize is zero, it is
    // ignored, so we use a non-zero value that has the same
    // effect. Without this, the size won't shrink to zero when
    // transitioning from an agenda with events to one without.
    height = MAX(height, 0.001);
    self.preferredContentSize = NSMakeSize(NSWidth(_tv.frame), height);
}

- (void)updateViewConstraints
{
    // Tell _tv that row heights need to be recalculated.
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [_tv numberOfRows])];
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0];
    [_tv noteHeightOfRowsWithIndexesChanged:indexSet];
    [NSAnimationContext endGrouping];
    [super updateViewConstraints];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor
{
    _backgroundColor = backgroundColor;
    _tv.backgroundColor = backgroundColor;
}

- (void)setShowLocation:(BOOL)showLocation
{
    if (_showLocation != showLocation) {
        _showLocation = showLocation;
        [self reloadData];
    }
}

- (void)reloadData
{
    [_tv reloadData];
    [_tv scrollRowToVisible:0];
    [[_tv enclosingScrollView] flashScrollers];
    [self.view setNeedsLayout:YES];
}

- (void)themeChanged:(id)sender
{
    [_tv.enclosingScrollView.verticalScroller setNeedsDisplay];
    self.backgroundColor = [[Themer shared] mainBackgroundColor];
    [self reloadData];
}

#pragma mark -
#pragma mark Context Menu

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    // Invoked just before menu is to be displayed.
    // Show a context menu ONLY for non-group rows.
    [menu removeAllItems];
    if (_tv.clickedRow < 0 || [self tableView:_tv isGroupRow:_tv.clickedRow]) return;
    [menu addItemWithTitle:NSLocalizedString(@"Copy", nil) action:@selector(copyEventToPasteboard:) keyEquivalent:@""];
}

- (void)copyEventToPasteboard:(id)sender
{
    if (_tv.clickedRow < 0 || [self tableView:_tv isGroupRow:_tv.clickedRow]) return;
    
    static NSDateIntervalFormatter *intervalFormatter = nil;
    if (intervalFormatter == nil) {
        intervalFormatter = [NSDateIntervalFormatter new];
        intervalFormatter.dateStyle = NSDateIntervalFormatterMediumStyle;
    }
    
    AgendaEventCell *cell = [_tv viewAtColumn:0 row:_tv.clickedRow makeIfNecessary:NO];
    
    if (cell == nil) return; // should not happen
    
    intervalFormatter.timeZone  = [NSTimeZone localTimeZone];
    // All-day events don't show time.
    intervalFormatter.timeStyle = cell.eventInfo.event.isAllDay
        ? NSDateIntervalFormatterNoStyle
        : NSDateIntervalFormatterShortStyle;
    // For single-day events, end date is same as start date.
    NSDate *endDate = cell.eventInfo.isSingleDay
        ? cell.eventInfo.event.startDate
        : cell.eventInfo.event.endDate;
    // Interval formatter just prints single date when from == to.
    NSString *duration = [intervalFormatter stringFromDate:cell.eventInfo.event.startDate toDate:endDate];

    NSString *eventText = [NSString stringWithFormat:@"%@%@%@\n%@\n",
                           cell.titleTextField.stringValue,
                           cell.locationTextField.stringValue.length > 0 ? @"\n" : @"",
                           cell.locationTextField.stringValue,
                           duration];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] writeObjects:@[eventText]];
}

#pragma mark -
#pragma mark TableView delegate/datasource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.events == nil ? 0 : self.events.count;
}

- (NSTableRowView *)tableView:(MoTableView *)tableView rowViewForRow:(NSInteger)row
{
    AgendaRowView *rowView = [_tv makeViewWithIdentifier:@"RowView" owner:self];
    if (rowView == nil) {
        rowView = [AgendaRowView new];
        rowView.identifier = @"RowView";
    }
    rowView.isHovered = tableView.hoverRow == row;
    return rowView;
}

- (NSView *)tableView:(MoTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSView *v = nil;
    id obj = self.events[row];
    
    if ([obj isKindOfClass:[NSDate class]]) {
        AgendaDateCell *cell = [_tv makeViewWithIdentifier:kDateCellIdentifier owner:self];
        if (cell == nil) cell = [AgendaDateCell new];
        cell.date = obj;
        cell.dayTextField.stringValue = [self dayStringForDate:obj];
        cell.DOWTextField.stringValue = [self DOWStringForDate:obj];
        cell.dayTextField.textColor = [[Themer shared] agendaDayTextColor];
        cell.DOWTextField.textColor = [[Themer shared] agendaDOWTextColor];
        v = cell;
    }
    else {
        EventInfo *info = obj;
        AgendaEventCell *cell = [_tv makeViewWithIdentifier:kEventCellIdentifier owner:self];
        if (!cell) cell = [AgendaEventCell new];
        cell.eventInfo = info;
        cell.toolTip = self.showLocation ? nil : info.event.location;
        [self populateEventCell:cell withInfo:info showLocation:self.showLocation];
        cell.dim = NO;
        // If event's endDate is today and is past, dim event.
        if (!info.isStartDate && !info.isAllDay &&
            [self.nsCal isDateInToday:info.event.endDate] &&
            [NSDate.date compare:info.event.endDate] == NSOrderedDescending) {
            // This looks pointless, but I'm clearing the attributes so the
            // next line where I set textColor will color the whole string.
            cell.titleTextField.textColor = [[Themer shared] agendaEventDateTextColor];
            cell.dim = YES;
        }
        v = cell;
    }
    return v;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    // Keep a cell around for measuring event cell height.
    static AgendaEventCell *eventCell = nil;
    static CGFloat dateCellHeight = 0;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        eventCell = [AgendaEventCell new];
        AgendaDateCell *dateCell = [AgendaDateCell new];
        dateCell.frame = NSMakeRect(0, 0, NSWidth(_tv.frame), 999); // only width is important here
        dateCell.dayTextField.integerValue = 21;
        dateCellHeight = dateCell.height;
    });
    
    CGFloat height = dateCellHeight;
    id obj = self.events[row];
    if ([obj isKindOfClass:[EventInfo class]]) {
        eventCell.frame = NSMakeRect(0, 0, NSWidth(_tv.frame), 999); // only width is important here
        [self populateEventCell:eventCell withInfo:obj showLocation:self.showLocation];
        height = eventCell.height;
    }
    return height;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    return [self.events[row] isKindOfClass:[NSDate class]];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return NO; // disable selection
}

- (void)tableView:(MoTableView *)tableView didHoverOverRow:(NSInteger)hoveredRow
{
    if (hoveredRow == -1 || [self tableView:_tv isGroupRow:hoveredRow]) {
        hoveredRow = -1;
    }
    for (NSInteger row = 0; row < [_tv numberOfRows]; row++) {
        if (![self tableView:_tv isGroupRow:row]) {
            AgendaRowView *rowView = [_tv rowViewAtRow:row makeIfNecessary:NO];
            rowView.isHovered = (row == hoveredRow);
        }
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(agendaHoveredOverRow:)]) {
        [self.delegate agendaHoveredOverRow:hoveredRow];
    }
}

#pragma mark -
#pragma mark Format Agenda Strings

- (NSString *)dayStringForDate:(NSDate *)date
{
    static NSDateFormatter *dateFormatter = nil;
    if (dateFormatter == nil) {
        dateFormatter = [NSDateFormatter new];
    }
    dateFormatter.timeZone = [NSTimeZone localTimeZone];
    [dateFormatter setLocalizedDateFormatFromTemplate:@"dMMM"];
    return [dateFormatter stringFromDate:date];
}

- (NSString *)DOWStringForDate:(NSDate *)date
{
    static NSDateFormatter *dateFormatter = nil;
    if (dateFormatter == nil) {
        dateFormatter = [NSDateFormatter new];
    }
    dateFormatter.timeZone = [NSTimeZone localTimeZone];
    if ([self.nsCal isDateInToday:date] || [self.nsCal isDateInTomorrow:date]) {
        dateFormatter.doesRelativeDateFormatting = YES;
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterNoStyle;
    }
    else {
        dateFormatter.doesRelativeDateFormatting = NO;
        [dateFormatter setLocalizedDateFormatFromTemplate:@"EEEE"];
    }
    return [dateFormatter stringFromDate:date];
}

- (void)populateEventCell:(AgendaEventCell *)cell withInfo:(EventInfo *)info showLocation:(BOOL)showLocation
{
    static NSDateFormatter *timeFormatter = nil;
    static NSDateIntervalFormatter *intervalFormatter = nil;
    if (timeFormatter == nil) {
        timeFormatter = [NSDateFormatter new];
        timeFormatter.dateStyle = NSDateFormatterNoStyle;
        timeFormatter.timeStyle = NSDateFormatterShortStyle;
    }
    if (intervalFormatter == nil) {
        intervalFormatter = [NSDateIntervalFormatter new];
        intervalFormatter.dateStyle = NSDateIntervalFormatterNoStyle;
        intervalFormatter.timeStyle = NSDateIntervalFormatterShortStyle;
    }
    NSString *title = @"";
    NSString *location = @"";
    NSString *duration = @"";
    timeFormatter.timeZone  = [NSTimeZone localTimeZone];
    intervalFormatter.timeZone  = [NSTimeZone localTimeZone];
    
    if (info && info.event) {
        if (info.event.title) title = info.event.title;
        if (info.event.location) location = info.event.location;
    }
    
    // Hide location row IF !showLocation OR there's no location string.
    [cell.grid rowAtIndex:1].hidden = (!showLocation || location.length == 0);
    
    // Hide duration row for all day events.
    [cell.grid rowAtIndex:2].hidden = info.isAllDay;
    
    if (info.isAllDay == NO) {
        if (info.isStartDate == YES) {
            if (info.event.startDate != nil) {
                duration = [timeFormatter stringFromDate:info.event.startDate];
            }
        }
        else if (info.isEndDate == YES) {
            if (info.event.endDate != nil) {
                NSString *ends = NSLocalizedString(@"ends", @"Spanning event ends");
                duration = [NSString stringWithFormat:@"%@ %@", ends, [timeFormatter stringFromDate:info.event.endDate]];
            }
        }
        else {
            if (info.event.startDate != nil && info.event.endDate != nil) {
                duration = [intervalFormatter stringFromDate:info.event.startDate toDate:info.event.endDate];
            }
        }
        // If the locale is English and we are in 12 hour time,
        // remove :00 from the time. Effect is 3:00 PM -> 3 PM.
        if ([[[NSLocale currentLocale] localeIdentifier] hasPrefix:@"en"]) {
            if ([[timeFormatter dateFormat] rangeOfString:@"a"].location != NSNotFound) {
                duration = [duration stringByReplacingOccurrencesOfString:@":00" withString:@""];
            }
        }
    }
    cell.titleTextField.stringValue = title;
    cell.titleTextField.textColor = [[Themer shared] agendaEventTextColor];
    cell.locationTextField.stringValue = location;
    cell.locationTextField.textColor = [[Themer shared] agendaEventDateTextColor];
    cell.durationTextField.stringValue = duration;
    cell.durationTextField.textColor = [[Themer shared] agendaEventDateTextColor];
}

#pragma mark -
#pragma mark Dim past events

- (void)dimEventsIfNecessary
{
    // If the user has the window showing, reload the agenda cells.
    // This will redraw the events, dimming if necessary.
    if (self.view.window.isVisible) {
        [_tv reloadData];
    }
}

@end

#pragma mark -
#pragma mark ThemedScroller

// =========================================================================
// ThemedScroller
// =========================================================================

@implementation ThemedScroller

+ (BOOL)isCompatibleWithOverlayScrollers {
    return self == [ThemedScroller class];
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
    [[[Themer shared] mainBackgroundColor] set];
    NSRectFill(slotRect);
}

@end

#pragma mark -
#pragma mark Agenda Row View

// =========================================================================
// AgendaRowView
// =========================================================================

@implementation AgendaRowView

- (void)drawRect:(NSRect)dirtyRect
{
    if (self.isGroupRowStyle) {
        [[self backgroundColor] set]; // tableView's background color
        NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
        NSRect r = NSMakeRect(4, 3, self.bounds.size.width - 8, 1);
        [[[Themer shared] agendaDividerColor] set];
        NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
    }
    else {
        [super drawRect:dirtyRect];
    }
}

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
    [super drawBackgroundInRect:dirtyRect];
    if (self.isHovered) {
        [[[Themer shared] agendaHoverColor] set];
        NSRect rect = NSInsetRect(self.bounds, 2, 1);
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] fill];
    }
}

- (void)setIsHovered:(BOOL)isHovered {
    if (_isHovered != isHovered) {
        _isHovered = isHovered;
        [self setNeedsDisplay:YES];
    }
}

@end

#pragma mark -
#pragma mark Agenda Date and Event cells

// =========================================================================
// AgendaDateCell
// =========================================================================

@implementation AgendaDateCell

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.identifier = kDateCellIdentifier;
        _dayTextField = [NSTextField labelWithString:@""];
        _dayTextField.translatesAutoresizingMaskIntoConstraints = NO;
        _dayTextField.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _dayTextField.textColor = [[Themer shared] agendaDayTextColor];
        [_dayTextField setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        
        _DOWTextField = [NSTextField labelWithString:@""];
        _DOWTextField.translatesAutoresizingMaskIntoConstraints = NO;
        _DOWTextField.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        _DOWTextField.textColor = [[Themer shared] agendaDOWTextColor];

        [self addSubview:_dayTextField];
        [self addSubview:_DOWTextField];
        MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:self metrics:nil views:NSDictionaryOfVariableBindings(_dayTextField, _DOWTextField)];
        [vfl :@"H:|-4-[_DOWTextField]-(>=4)-[_dayTextField]-4-|" :NSLayoutFormatAlignAllLastBaseline];
        [vfl :@"V:|-6-[_dayTextField]-1-|"];
    }
    return self;
}

- (CGFloat)height
{
    // The height of the textfield plus the height of the
    // top and bottom marigns.
    return [_dayTextField intrinsicContentSize].height + 7; // 6+1=top+bottom margin
}

@end

// =========================================================================
// AgendaEventCell
// =========================================================================

@implementation AgendaEventCell

- (instancetype)init
{
    // Convenience function for making labels.
    NSTextField* (^label)() = ^NSTextField* () {
        NSTextField *lbl = [NSTextField labelWithString:@""];
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        lbl.font = [NSFont systemFontOfSize:11];
        lbl.lineBreakMode = NSLineBreakByWordWrapping;
        lbl.cell.truncatesLastVisibleLine = YES;
        return lbl;
    };
    self = [super init];
    if (self) {
        self.identifier = kEventCellIdentifier;
        _titleTextField = label();
        _titleTextField.maximumNumberOfLines = 1;
        _locationTextField = label();
        _locationTextField.maximumNumberOfLines = 2;
        _durationTextField = label();
        _grid = [NSGridView gridViewWithViews:@[@[_titleTextField],
                                                @[_locationTextField],
                                                @[_durationTextField]]];
        _grid.translatesAutoresizingMaskIntoConstraints = NO;
        _grid.rowSpacing = 0;
        [self addSubview:_grid];
        MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:self metrics:nil views:NSDictionaryOfVariableBindings(_grid)];
        [vfl :@"H:|-16-[_grid]-16-|"];
        [vfl :@"V:|-3-[_grid]"];
    }
    return self;
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    // Setting preferredMaxLayoutWidth allows us to calculate height
    // after word-wrapping.
    // 32 = 16 + 16 = leading + trailing margins
    _titleTextField.preferredMaxLayoutWidth = NSWidth(frame) - 32;
    _locationTextField.preferredMaxLayoutWidth = NSWidth(frame) - 32;
    _durationTextField.preferredMaxLayoutWidth = NSWidth(frame) - 32;
}

- (CGFloat)height
{
    // The height of the textfields (which may have word-wrapped)
    // plus the height of the top and bottom marigns.
    // top margin + bottom margin = 3 + 3 = 6
    CGFloat locationHeight = [_grid rowAtIndex:1].isHidden ? 0 : _locationTextField.intrinsicContentSize.height;
    CGFloat durationHeight = [_grid rowAtIndex:2].isHidden ? 0 : _durationTextField.intrinsicContentSize.height;
    return _titleTextField.intrinsicContentSize.height + locationHeight + durationHeight + 6;
}

- (void)setDim:(BOOL)dim {
    if (_dim != dim) {
        _dim = dim;
        [self setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGFloat alpha = self.dim ? 0.5 : 1;
    NSColor *dotColor = self.eventInfo.event.calendar.color;
    [[dotColor colorWithAlphaComponent:alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6, NSHeight(self.bounds) - 13, 6, 6)] fill];
}

@end
