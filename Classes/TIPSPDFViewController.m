//
//  TIPSPDFViewController.m
//  PSPDFKit-Titanium
//
//  Copyright (c) 2011-2015 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY AUSTRIAN COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import "TIPSPDFViewController.h"
#import "TIPSPDFViewControllerProxy.h"
#import "ComPspdfkitModule.h"
#import <objc/runtime.h>

NSString *const kTempAnnotationIdSuffix = @"_tempPitAnn";

@interface PSPDFViewController (Internal)
- (void)delegateDidShowController:(id)viewController embeddedInController:(id)controller options:(NSDictionary *)options animated:(BOOL)animated;
- (BOOL)presentViewController:(UIViewController *)controller options:(nullable NSDictionary<NSString *, id> *)options animated:(BOOL)animated sender:(nullable id)sender completion:(nullable void (^)(void))completion;
@end

@implementation TIPSPDFViewController

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Lifecycle

- (void)dealloc {
    PSTiLog(@"dealloc: %@", self)
    self.proxy = nil; // forget proxy
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public

- (void)setProxy:(TIPSPDFViewControllerProxy *)proxy {
    if (proxy != _proxy) {
        [_proxy forgetSelf];
        _proxy = proxy;
        [proxy rememberSelf];
    }
}

- (void)closeControllerAnimated:(BOOL)animated {
    PSCLog(@"closing controller animated: %d", animated);
    [self dismissViewControllerAnimated:animated completion:NULL];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIViewController

- (void)loadView {
    [super loadView];
    
    // NOTE: KK: 04.04.2024: Due to video link annotations no longer working on iOS SDK 17
    // (due to Apple changing URL/NSURL parsing from the obsolete RFC 1738/1808 standard to RFC 3986)
    // below we're dynamically replacing those video link annotations using the `URLAction.invalidURLString` of a given broken annotation
    // (stripping out all the display options between `[` and `]` chars in the original URLs)
    if (@available(iOS 17.0, *)) {
        [self handleDynamicAnnotations];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.navigationController.isBeingDismissed) {
        // Workaround for the issues popover views staying on screen after dismissing PDF view controller
        if (self.presentedController != nil) {
            [self.presentedController dismissViewControllerAnimated:NO completion:NULL];
        }
        
        [self.proxy fireEvent:@"willCloseController" withObject:nil];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    if (self.navigationController.isBeingDismissed) {
        [self.proxy fireEvent:@"didCloseController" withObject:nil];
        self.proxy = nil;
    }
}

// If we return YES here, UIWindow leaks our controller in the Titanium configuration.
- (BOOL)canBecomeFirstResponder {
    return NO;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Dynamic Annotations

- (void)handleDynamicAnnotations {
    [self removeTemporaryAnnotations];
    [self hideOriginalBrokenAnnotations];
    [self addTemporaryAnnotations];
}

- (NSArray<PSPDFLinkAnnotation *> *)allLinkAnnotations {
    NSMutableArray<PSPDFLinkAnnotation *> *annotations = [NSMutableArray array];
    NSDictionary<NSNumber *, NSArray<PSPDFLinkAnnotation *> *> *annotationsDict = [self.document allAnnotationsOfType:PSPDFAnnotationTypeLink];
    
    for (NSArray<PSPDFLinkAnnotation *> *pageAnnotations in annotationsDict.allValues) {
        [annotations addObjectsFromArray:pageAnnotations];
    }
    return [annotations copy];
}

- (NSArray<PSPDFLinkAnnotation *> *)allBrokenLinkAnnotations {
    NSMutableArray<PSPDFLinkAnnotation *> *annotations = [NSMutableArray array];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PSPDFLinkAnnotation *evaluatedObject, NSDictionary *bindings) {
        NSString *invalidURLString = evaluatedObject.URLAction.invalidURLString;
        return invalidURLString.length > 0 &&
               [invalidURLString containsString:@"%5B"] &&
               [invalidURLString containsString:@"%5D"] &&
               [invalidURLString containsString:@"/videos/"];
    }];
    NSArray<PSPDFLinkAnnotation *> *filteredAnnotations = [[self allLinkAnnotations] filteredArrayUsingPredicate:predicate];
    return filteredAnnotations;
}

- (void)removeTemporaryAnnotations {
    NSArray<PSPDFLinkAnnotation *> *linkAnnotations = [self allLinkAnnotations];
    if (linkAnnotations.count > 0) {
        NSMutableArray<PSPDFAnnotation *> *tempAnnotations = [NSMutableArray array];
        for (PSPDFAnnotation *annotation in linkAnnotations) {
            if ([annotation.name hasSuffix:kTempAnnotationIdSuffix]) {
                [tempAnnotations addObject:annotation];
            }
        }
        if (tempAnnotations.count > 0) {
            [self.document removeAnnotations:tempAnnotations options:nil];
        }
    }
}

- (void)hideOriginalBrokenAnnotations {
    NSArray<PSPDFLinkAnnotation *> *linkAnnotations = [self allBrokenLinkAnnotations];
    if (linkAnnotations.count > 0) {
        for (PSPDFAnnotation *annotation in linkAnnotations) {
            annotation.hidden = YES;
            annotation.alpha = 0.0;
        }
    }
}

- (void)addTemporaryAnnotations {
    NSArray<PSPDFLinkAnnotation *> *linkAnnotations = [self allBrokenLinkAnnotations];
    NSMutableArray<PSPDFAnnotation *> *annotationsToAdd = [NSMutableArray array];
    __block BOOL shouldRemoveCache = NO;
    
    for (PSPDFLinkAnnotation *annotation in linkAnnotations) {
        NSString *originalURLString = annotation.URLAction.invalidURLString;
        if (originalURLString == nil) {
            continue;
        }
        NSURL *newURL = [self getVideoURLWithoutOptions:originalURLString];
        PSPDFLinkAnnotation *newVideoAnnotation = [[PSPDFLinkAnnotation alloc] initWithURL:newURL];
        newVideoAnnotation.boundingBox = annotation.boundingBox;
        newVideoAnnotation.pageIndex = annotation.pageIndex;
        newVideoAnnotation.name = [NSString stringWithFormat:@"%@%@", annotation.uuid, kTempAnnotationIdSuffix];
        
        [annotationsToAdd addObject:newVideoAnnotation];
    }
    if (annotationsToAdd.count > 0) {
        shouldRemoveCache = YES;
        [self.document addAnnotations:annotationsToAdd options:nil];
    }
    NSError *error = nil;
    if ([self.document saveWithOptions:nil error:&error]) {
        if (shouldRemoveCache) {
            [PSPDFKitGlobal.sharedInstance.cache removeCacheForDocument:self.document];
        }
    } else {
        NSLog(@"[ERROR] PSPDF Document not saved, error: %@", error.localizedDescription);
    }
}

- (NSURL *)getVideoURLWithoutOptions:(NSString *)originalLink {
    NSString *pattern = @"%5B.*?%5D";
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];

    NSString *urlStringWithoutOptions = @"";
    if (!error) {
        urlStringWithoutOptions = [regex stringByReplacingMatchesInString:originalLink options:0 range:NSMakeRange(0, [originalLink length]) withTemplate:@""];
    } else {
        NSLog(@"Error creating regex: %@", error.localizedDescription);
    }
    return [NSURL URLWithString:urlStringWithoutOptions];
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - PSPDFViewController

- (BOOL)presentViewController:(UIViewController *)controller options:(nullable NSDictionary<NSString *, id> *)options animated:(BOOL)animated sender:(nullable id)sender completion:(nullable void (^)(void))completion {
    [super presentViewController:controller options:options animated:animated sender:sender completion:completion];
    
    self.presentedController = controller;
    return YES;
}

- (void)delegateDidShowController:(id)viewController embeddedInController:(id)controller options:(NSDictionary *)options animated:(BOOL)animated {
    [super delegateDidShowController:viewController embeddedInController:controller options:options animated:animated];

    // Fire event when a popover is displayed.
    [self.proxy fireEvent:@"didPresentPopover" withObject:viewController];
}

@end
