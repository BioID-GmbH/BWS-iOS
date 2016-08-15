//
//  ViewController.h
//  BioIDSample
//
//  Copyright © 2015 BioID. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CaptureViewController.h"

@interface ViewController : UIViewController<UITabBarDelegate, CaptureDelegate>
@property (weak, nonatomic) IBOutlet UITabBar *tabBar;
@property (readonly) CaptureConfiguration *captureConfiguration;
@end

