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
