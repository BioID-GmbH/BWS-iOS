//
//  ViewController.m
//  BioIDSample
//
//  Copyright © 2015 BioID. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tabBar setDelegate:self];
    
    // Ask at the first use of the app if the camera access is allowed - this state called AuthorizationStatusNotDetermined!
    // If the user not allow to access the camera the CaptureViewController handle this by displaying
    // the message 'No camera available' and abort the process.
    // If the user disable camera access later on, the CaptureViewController do the same. We don`t ask each
    // time for camera access but handle the states Authorized, Restricted, Denied.
    // Only AuthorizationStatusNotDetermined should be done before calling CaptureViewController!!!
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusNotDetermined) {
        NSLog(@"Camera access not determined. Ask for permission");
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            // nothing to do ...
         }];
    }
         
    // HERE is only initialization of tabBarItems
    
    // set image for selected and unselected tab bar items
    for (UITabBarItem *tabBarItem in self.tabBar.items) {
        tabBarItem.image = [tabBarItem.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        tabBarItem.selectedImage = [tabBarItem.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        
        if (tabBarItem.tag == 1) {
            [tabBarItem setTitle:NSLocalizedString(@"Enroll", nil)];
        }
        else if (tabBarItem.tag == 2) {
            [tabBarItem setTitle:NSLocalizedString(@"Verify", nil)];
        }
    }
    
    // Get iOS default tintColor
    UIColor *defaultTintColor = self.view.tintColor;
    // set text tint color
    [[UITabBarItem appearance] setTitleTextAttributes:@{ NSForegroundColorAttributeName: defaultTintColor} forState:UIControlStateNormal];
    [[UITabBarItem appearance] setTitleTextAttributes:@{ NSForegroundColorAttributeName: defaultTintColor} forState:UIControlStateSelected];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    
    // HERE we are calling the BioID CaptureViewController for enrollment or verification.
    // Use the captureConfiguration to specify if you want to perform an enrollment or verification.
    
    // Choose which trait(s) you want to use
    // Possible values are for single trait "Face" or "Periocular"
    // Or togehter "Face,Periocular" (multimodal)
    NSString* traits = @"Face,Periocular";
    
    if (item.tag == 1) {
        // Create CaptureConfiguration for enrollment
        _captureConfiguration = [[CaptureConfiguration alloc] initForEnrollment:traits];
        [self performSegueWithIdentifier:@"showCaptureView" sender:self];
    }
    else if (item.tag == 2) {
        // Create CaptureConfiguration for verification - challenge is disabled!
        _captureConfiguration = [[CaptureConfiguration alloc] initForVerification:FALSE withTraits:traits];
        [self performSegueWithIdentifier:@"showCaptureView" sender:self];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    // HERE we are set the captureConfiguration to the CaptureViewController
    
    if ([[segue identifier] isEqualToString:@"showCaptureView"]) {
        CaptureViewController *viewController = [segue destinationViewController];
        
        // Set captureConfiguration to the CaptureViewController
        viewController.configuration = self.captureConfiguration;
        
        // Set callback to self
        viewController.callback = self;
    }
}

// Implement the biometricTaskFinished function to receive the result if the biometric task finished
- (void)biometricTaskFinished:(CaptureConfiguration *)data withSuccess:(BOOL)success {
    
    // HERE you get the result of the biometric task from the CaptureViewController
    
    NSString *biometricResult;
    if (success) {
        biometricResult = @"Successful ";
    }
    else {
        biometricResult = @"Failed ";
    }

    if (data.performEnrollment) {
        biometricResult = [biometricResult stringByAppendingString:@"Enrollment"];
    }
    else {
        biometricResult = [biometricResult stringByAppendingString:@"Verification"];
    }
    
    NSLog(@"%@", biometricResult);
}

@end
