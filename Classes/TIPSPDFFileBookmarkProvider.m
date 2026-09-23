//
//  TIPSPDFFileBookmarkProvider.m
//  PSPDFKit-Titanium
//

#import "TIPSPDFFileBookmarkProvider.h"

static NSString *const TIPSPDFBookmarkFileVersionKey = @"version";
static NSString *const TIPSPDFBookmarkFileBookmarksKey = @"bookmarks";
static NSString *const TIPSPDFBookmarkIdentifierKey = @"identifier";
static NSString *const TIPSPDFBookmarkPageIndexKey = @"pageIndex";
static NSString *const TIPSPDFBookmarkNameKey = @"name";
static NSString *const TIPSPDFBookmarkSortKeyKey = @"sortKey";
static NSInteger const TIPSPDFBookmarkFileVersion = 1;

@interface TIPSPDFFileBookmarkProvider ()
@property (nonatomic) NSURL *fileURL;
@property (nonatomic) NSUInteger pageCount;
@property (nonatomic) NSMutableArray<PSPDFBookmark *> *storedBookmarks; // guarded by @synchronized(self)
@property (nonatomic) BOOL dirty;                                         // guarded by @synchronized(self)
@end

@implementation TIPSPDFFileBookmarkProvider

- (instancetype)initWithFileURL:(NSURL *)fileURL pageCount:(NSUInteger)pageCount {
    if ((self = [super init])) {
        _fileURL = fileURL;
        _pageCount = pageCount;
        _storedBookmarks = [self loadBookmarks];
    }
    return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFBookmarkProvider

- (NSArray<PSPDFBookmark *> *)bookmarks {
    @synchronized(self) {
        if (self.pageCount == 0) {
            return [self.storedBookmarks copy];
        }
        NSMutableArray<PSPDFBookmark *> *visibleBookmarks = [NSMutableArray arrayWithCapacity:self.storedBookmarks.count];
        for (PSPDFBookmark *bookmark in self.storedBookmarks) {
            if (bookmark.pageIndex < self.pageCount) {
                [visibleBookmarks addObject:bookmark];
            }
        }
        return visibleBookmarks;
    }
}

- (BOOL)addBookmark:(PSPDFBookmark *)bookmark {
    // Only page bookmarks can be serialized by this provider; let the next provider handle the rest.
    if (![bookmark.action isKindOfClass:PSPDFGoToAction.class] || bookmark.pageIndex == NSNotFound) {
        return NO;
    }

    @synchronized(self) {
        // Updated versions of already owned bookmarks (rename, re-order) are sent through `addBookmark:` too.
        NSUInteger existingIndex = [self indexOfBookmarkWithIdentifier:bookmark.identifier];
        if (existingIndex != NSNotFound) {
            self.storedBookmarks[existingIndex] = bookmark;
        } else {
            [self.storedBookmarks addObject:bookmark];
        }
        self.dirty = YES;
        [self writeBookmarksIfNeeded];
    }
    return YES;
}

- (BOOL)removeBookmark:(PSPDFBookmark *)bookmark {
    @synchronized(self) {
        NSUInteger existingIndex = [self indexOfBookmarkWithIdentifier:bookmark.identifier];
        if (existingIndex == NSNotFound) {
            return NO;
        }
        [self.storedBookmarks removeObjectAtIndex:existingIndex];
        self.dirty = YES;
        [self writeBookmarksIfNeeded];
    }
    return YES;
}

- (void)save {
    @synchronized(self) {
        [self writeBookmarksIfNeeded];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private

- (NSUInteger)indexOfBookmarkWithIdentifier:(NSString *)identifier {
    if (identifier == nil) {
        return NSNotFound;
    }
    return [self.storedBookmarks indexOfObjectPassingTest:^BOOL(PSPDFBookmark *storedBookmark, NSUInteger idx, BOOL *stop) {
        return [storedBookmark.identifier isEqualToString:identifier];
    }];
}

- (NSMutableArray<PSPDFBookmark *> *)loadBookmarks {
    NSMutableArray<PSPDFBookmark *> *bookmarks = [NSMutableArray array];

    NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
    if (data.length == 0) {
        return bookmarks;
    }

    NSError *error;
    NSDictionary *root = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (![root isKindOfClass:NSDictionary.class]) {
        NSLog(@"[PSPDFKit-Titanium] Unable to read bookmarks from %@: %@", self.fileURL.path, error.localizedDescription);
        return bookmarks;
    }

    NSArray *entries = root[TIPSPDFBookmarkFileBookmarksKey];
    if (![entries isKindOfClass:NSArray.class]) {
        return bookmarks;
    }

    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;

        NSString *identifier = entry[TIPSPDFBookmarkIdentifierKey];
        NSNumber *pageIndex = entry[TIPSPDFBookmarkPageIndexKey];
        if (![identifier isKindOfClass:NSString.class] || identifier.length == 0 || ![pageIndex isKindOfClass:NSNumber.class]) continue;

        NSString *name = [entry[TIPSPDFBookmarkNameKey] isKindOfClass:NSString.class] ? entry[TIPSPDFBookmarkNameKey] : nil;
        NSNumber *sortKey = [entry[TIPSPDFBookmarkSortKeyKey] isKindOfClass:NSNumber.class] ? entry[TIPSPDFBookmarkSortKeyKey] : nil;
        PSPDFGoToAction *action = [[PSPDFGoToAction alloc] initWithPageIndex:pageIndex.unsignedIntegerValue];
        PSPDFBookmark *bookmark = [[PSPDFBookmark alloc] initWithIdentifier:identifier action:action name:name sortKey:sortKey];
        if (bookmark) {
            [bookmarks addObject:bookmark];
        }
    }
    return bookmarks;
}

// Must be called while holding @synchronized(self).
- (void)writeBookmarksIfNeeded {
    if (!self.dirty) {
        return;
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:self.storedBookmarks.count];
    for (PSPDFBookmark *bookmark in self.storedBookmarks) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[TIPSPDFBookmarkIdentifierKey] = bookmark.identifier;
        entry[TIPSPDFBookmarkPageIndexKey] = @(bookmark.pageIndex);
        if (bookmark.name) entry[TIPSPDFBookmarkNameKey] = bookmark.name;
        if (bookmark.sortKey) entry[TIPSPDFBookmarkSortKeyKey] = bookmark.sortKey;
        [entries addObject:entry];
    }
    NSDictionary *root = @{TIPSPDFBookmarkFileVersionKey : @(TIPSPDFBookmarkFileVersion), TIPSPDFBookmarkFileBookmarksKey : entries};

    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data) {
        NSLog(@"[PSPDFKit-Titanium] Unable to serialize bookmarks: %@", error.localizedDescription);
        return;
    }

    NSURL *directoryURL = self.fileURL.URLByDeletingLastPathComponent;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[PSPDFKit-Titanium] Unable to create bookmarks directory %@: %@", directoryURL.path, error.localizedDescription);
        return;
    }
    if (![data writeToURL:self.fileURL options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[PSPDFKit-Titanium] Unable to write bookmarks to %@: %@", self.fileURL.path, error.localizedDescription);
        return;
    }
    self.dirty = NO;
}

@end
