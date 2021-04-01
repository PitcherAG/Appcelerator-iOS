#import "SharingViewController.h"


@implementation SharingViewController

- (void)configureMailComposeViewController:(MFMailComposeViewController *)mailComposeViewController {
    [mailComposeViewController setMailComposeDelegate:self];
}


#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(nullable NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
    if (result == MFMailComposeResultSent) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PDFSharingEmailSent" object:self];
    }
}

@end
