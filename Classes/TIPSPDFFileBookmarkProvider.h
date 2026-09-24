//
//  TIPSPDFFileBookmarkProvider.h
//  PSPDFKit-Titanium
//

#import <PSPDFKit/PSPDFKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Bookmark provider that stores bookmarks in a property list file next to the document's
/// other data (inside `-[PSPDFDocument dataDirectory]`), instead of inside the PDF.
///
/// Since PSPDFKit 6, bookmarks are stored in the PDF's XMP metadata by default. When
/// `annotationSaveMode` is `PSPDFAnnotationSaveModeExternalFile` the PDF is never written,
/// so bookmarks added by the user are lost when the document is closed. This provider
/// restores the pre-PSPDFKit 6 behavior (bookmarks kept in a separate file).
///
/// Only bookmarks with a `PSPDFGoToAction` (i.e. page bookmarks, the only kind that can be
/// created from the UI) are owned by this provider. Any other bookmark is passed on to the
/// next provider in the bookmark manager's list.
///
/// Changes are written to disk immediately (write-through), so persistence does not depend
/// on the document being saved.
@interface TIPSPDFFileBookmarkProvider : NSObject <PSPDFBookmarkProvider>

PSPDF_EMPTY_INIT_UNAVAILABLE

/// @param fileURL   The property list file used to load and store the bookmarks.
/// @param pageCount The number of pages of the document. Bookmarks pointing past the last page
///                  (e.g. after the file was replaced by a shorter version) are kept in the file,
///                  but are not exposed. Pass 0 to disable this filtering.
- (instancetype)initWithFileURL:(NSURL *)fileURL pageCount:(NSUInteger)pageCount NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSURL *fileURL;

@end

NS_ASSUME_NONNULL_END
