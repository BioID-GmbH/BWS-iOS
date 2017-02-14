//
//  CaptureViewController.m
//  BioIDSample
//
//  Copyright (c) 2015 BioID. All rights reserved.
//

#import "CaptureViewController.h"

@interface CaptureViewController ()

// class extension
- (BOOL)setupAVCapture;
- (void)teardownAVCapture;
@property AVCaptureSession *captureSession;

@end

@implementation CaptureViewController

@synthesize previewView;
@synthesize captureSession;


// Faces to be found continuously until the initial recording is triggered
static int const TRIGGER_TO_START = 5;
// Wait a moment for camera adjustment
static double const WAIT_FOR_CAMERA_ADJUSTMENT = 0.9;
// If no face was found (by client) upload the first image
static double const TRIGGER_INTERVAL = 3.0;
// Reaction time for a challenge
static double const CHALLENGE_RESPONSE_INTERVAL = 1.0;
// Seconds a message will be shown on the screen
static NSTimeInterval const MESSAGE_DISPLAY_TIME = 3.0;
static NSTimeInterval const MESSAGE_DISPLAY_TIME_SHORT = 1.7;
// Seconds after which the view will be dismissed if no activity (face finding/motion detection/...) was detected
static NSTimeInterval const INACTIVITY_TIMEOUT = 12;
// The threshold value given in percentage of complete motion (i.e. between 0 and 100)
static int const MIN_MOVEMENT_PERCENTAGE = 15;
// Maximum tries until failure is reported
static int const DEFAULT_MAX_TRIES = 3;
// Maximum tries until abort
static int const DEFAULT_MAX_NOFACE_FOUND = 3;
// Number of turns requested from the user during enrollment
static int const REQUIRED_TURNS = 3;
// Helper to calculate degree to radian
static CGFloat DegreesToRadians(CGFloat degrees)  { return degrees * M_PI / 180; }
// Used font in this controller
NSString *const BIOID_FONT = @"HelveticaNeue";

// Helper for time measurement
#define Start   NSDate *startTime = [NSDate date];
#define Stop    NSLog(@"Execution time: %.f", [startTime timeIntervalSinceNow]* -1000.0);


#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    faceFinderRunning = false;
    captureTriggered = false;
    capturing = false;
    
    uploaded = 0;
    uploading = 0;
    turnCount = 0;
    noFaceFound = 0;
    sequenceNumber = 0;
    
    requiredTurns = REQUIRED_TURNS;
    executions = DEFAULT_MAX_TRIES;

    // Receive notification if orientation is changed
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:nil];
    
    // Check permission of camera
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusAuthorized) {
        cameraAccess = [self setupAVCapture];
        [self createLayers];
    
        if (cameraAccess) {
            [self initFaceFinder];
        }
    }
    else {  // AVAuthorizationStatusDenied || AVAuthorizationStatusNotDetermined || AVAuthorizationStatusRestricted
        cameraAccess = NO;
        [self createLayers];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    if(!self.configuration) {
        [self abortViewController];
    }

    [self setLayers:[[UIDevice currentDevice] orientation]];
    
    if (cameraAccess == NO) {
        [self showMessageLayer:NSLocalizedString(@"NoCameraAvailable", nil)];
        displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME target:self selector:@selector(abortViewController) userInfo:nil repeats:NO];
        return;
    }
    
    [self.captureSession startRunning];

    [self showMessageLayer:NSLocalizedString(@"Initializing", nil)];
    [self.configuration ensureToken:^(NSError *error) {
        if(error) {
            [self reportError:[NSString stringWithFormat:NSLocalizedString(@"EnsureRegistrationAndInternet", nil), error.domain, (long)error.code] withTitle:NSLocalizedString(@"TokenRequestFailed", nil) allowContinue:NO];
        }
        else {
            [self hideMessageLayer];
            
            // Read BWS Token
            NSString *base64Decoded = [self base64UrlDecode:self.configuration.bwsToken];
            NSDictionary *jsonDictionary = [NSJSONSerialization JSONObjectWithData:[base64Decoded dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            taskFlags = [jsonDictionary[@"task"] integerValue];
            
            maxTries = (int)(taskFlags & TokenTaskMaxTriesMask);
            if (maxTries == 0) {
                maxTries = DEFAULT_MAX_TRIES;
            }
            executions = maxTries;
            
            NSString *challengeJson = jsonDictionary[@"challenge"];
            
            if (challengeJson) {
                NSLog(@"Challenge value: %@", challengeJson);
                challenges = [NSJSONSerialization JSONObjectWithData:[challengeJson dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            }
            
            if (self.configuration.performEnrollment) {
                [self showAlertView:NSLocalizedString(@"EnrollmentTitle", nil) message:NSLocalizedString(@"EnrollmentMessage", nil) continueAction:TRUE abortAction:FALSE ];
            }
            else {
                [self start];
            }
        }
    }];
    
    [super viewDidAppear:TRUE];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self.captureSession stopRunning];
    [self teardownAVCapture];
    [self cleanup];
    [super viewWillDisappear:TRUE];
}
    
- (void)cleanup {
    NSLog(@"-------------- Clean up ------------------");
   
    // Capture device & video output
    captureSession = nil;
    captureDevice = nil;
    previewLayer = nil;
    videoDataOutput = nil;
    videoDataOutputQueue = nil;
    
    // FaceDetector
    faceDetector = nil;
    detectorOptions = nil;
    
    // Motion detection
    templateBuffer = nil;
    
     // Timers
    [killTimer invalidate];
    killTimer = nil;
    [triggerTimer invalidate];
    triggerTimer = nil;
    [displayTimer invalidate];
    displayTimer = nil;
    [challengeResponseTimer invalidate];
    challengeResponseTimer = nil;
    
    // Challenges
    challenges = nil;
    currentChallenge = nil;
    
    [challengeSCNActions removeAllObjects];
    challengeSCNActions = nil;
    
    // NSURLSessionDataTask for uploads
    uploadTask1 = nil;
    uploadTask2 = nil;
    
    // SceneView for 3D head
    if (sceneView != nil) {
        [sceneView.scene setPaused:YES];
        sceneView.scene = nil;
        sceneView = nil;
    }
    // 3D head node
    headNode = nil;
    
    // Remove all subViews
    NSArray *subViews = [self.view subviews];
    for (UIView* view in subViews) {
        [view removeFromSuperview];
    }
    
    viewWithBlurredBackground = nil;
    statusViewBlurred = nil;
    alertView = nil;
    
    uploadTask1 = nil;
    uploadTask2 = nil;
    
    uploadProgressView1 = nil;
    uploadProgressView2 = nil;
    
    messageLabel = nil;
    statusLabel = nil;
    debugLabel = nil; 
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:NO completion:nil];
}

- (void)abortViewController {
    if (self.callback) {
        [self.callback biometricTaskFinished:self.configuration withSuccess:NO];
    }
    [self dismissViewController];
}

#pragma mark - Capturing & Workflow

- (void)start {
    NSLog(@"------------ Starting Capture ------------");
    
    capturing = false;
    captureTriggered = false;
    challengeRunning = false;
    faceFinderRunning = false;
    
    uploaded = 0;
    uploading = 0;
    recordings = 2;
    sequenceNumber = 0;
    continuousFoundFaces = 0;
    
    uploadTask1 = nil;
    uploadTask2 = nil;
    currentChallenge = nil;
    templateBuffer = nil;
    
    // Hide layers
    [self hideMessageLayer];
    [self hide3DHeadLayer];
    // Show Status Layer
    [self showStatusLayer:NSLocalizedString(@"StartingCapture", nil)];
    
    // This timer should not fire at all
    [self startDismissTimer:NSLocalizedString(@"NoCameraAvailable", nil)];
    // Auto trigger after some time
    [self startTriggerTimer];
    [self startWaitForCameraTimer];
    
    // Read the BWS TokenTask
    if ((taskFlags & TokenTaskChallengeResponse) == TokenTaskChallengeResponse &&
        (taskFlags & TokenTaskVerify) == TokenTaskVerify) {
        
        recordings = 4;
        currentChallenge = [challenges objectAtIndex:maxTries-executions];
        recordings = (int)[currentChallenge count] + 1;
        
        // Do challenge response action
        [self createActionForChallenge];
    }
    else {
        // Do live detection action
        [self createActionForLiveDetection];
    }
}

- (void)stop {
    NSLog(@"------------ Stopping Capture ------------");
    
    // Kill timers
    [self killTriggerTimer];
    [self killDismissTimer];
    
    // Hide layers
    [self hideStatusLayer];
    [self hide3DHeadLayer];
    
    [uploadProgressView1 setHidden:YES];
    [uploadProgressView2 setHidden:YES];
    
    capturing = false;
    captureTriggered = false;
    faceFinderRunning = false;
    
    continuousFoundFaces = 0;
    
    NSLog(@"------------ Stopped Capture -------------");
}

// Grab the live camera
// Notifes the delegate that a new video frame was written
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    
    int exifOrientation;
    UIImageOrientation imageOrientation = UIImageOrientationRight;
    
    switch (curDeviceOrientation) {
        case UIDeviceOrientationPortraitUpsideDown: {
            // Device oriented vertically, home button on the top
            imageOrientation = UIImageOrientationLeft;
            exifOrientation = kCGImagePropertyOrientationLeft;
            break;
        }
        case UIDeviceOrientationLandscapeLeft: {
            // Device oriented horizontally, home button on the right
            imageOrientation = UIImageOrientationDown;
            exifOrientation = kCGImagePropertyOrientationDown;
            break;
        }
        case UIDeviceOrientationLandscapeRight: {
            // Device oriented horizontally, home button on the left
            imageOrientation = UIImageOrientationUp;
            exifOrientation = kCGImagePropertyOrientationUp;
            break;
        }
        case UIDeviceOrientationPortrait:
            // ** Fall-through **
        default:
            // Device oriented vertically, home button on the bottom
            exifOrientation = kCGImagePropertyOrientationRight;
            break;
    }
    
    if (faceFinderRunning) {
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self show3DHeadLayer];
        });
        
        // Detect the face(s)
        NSDictionary *imageOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:exifOrientation] forKey:CIDetectorImageOrientation];
        NSArray *features = [faceDetector featuresInImage:ciImage options:imageOptions];
        
        // Features.count > 0 - one or more faces have been found
        if (features != NULL && features.count > 0) {
            if(++continuousFoundFaces == TRIGGER_TO_START) {
                captureTriggered = true;
            }
        }
        else {
            // No face found - reset the counter!
            continuousFoundFaces = 0;
        }
    }
    
    // Trigger capture
    if (!capturing && captureTriggered) {
        
        if (currentChallenge && !challengeRunning) {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self showStatusLayer:NSLocalizedString(@"CaptureTriggeredChallengeResponse", nil)];
            });
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self showStatusLayer:NSLocalizedString(@"CaptureTriggered", nil)];
            });
        }
        capturing = true;
    }
    
    if (capturing && !challengeWait) {
        // Create UIImage and rotate the image
        UIImage *image = [self imageFromSampleBuffer:sampleBuffer orientation:imageOrientation];
        UIImage *currentImage = [self scaleAndRotateImage:image];
        
        if (uploaded + uploading < recordings) {
            
            BOOL motion = true;
            if (templateBuffer) {
                // Calculate motion ...
                motion = [self motionDetection:currentImage];
            }
            
            if (motion) {
                id tag = @"any";
                if (challengeRunning) {
                    if (challengeStep < [currentChallenge count]) {
                        tag = [currentChallenge objectAtIndex:challengeStep];
                        challengeStep++;
                    }
                }
                else if (currentChallenge) {
                    challengeRunning = true;
                }
                
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    [self uploadSample:currentImage withTag:tag];
                });
                
                // create template for motion detection
                [self createTemplate:currentImage];
            }
        } 
    }
}

- (void)turnPosition {
    [self stop];
    [self showAlertView:NSLocalizedString(@"PleaseTurn", nil) message:NSLocalizedString(@"TurnBy90Degrees", nil) continueAction:TRUE abortAction:FALSE];
}

- (void)biometricTaskExecuted:(NSDictionary* )result {
    if ([[result valueForKey:@"Success"] boolValue]) {
        NSString* msg = NSLocalizedString(@"SuccessfulVerification", nil);
        if (self.configuration.performEnrollment) {
            msg = NSLocalizedString(@"SuccessfulEnrollment", nil);
        }
        [self showMessageLayer:msg];
        NSLog(@"%@!", msg);
        
        // Pass back the data to the caller
        if(self.callback) {
            [self.callback biometricTaskFinished:self.configuration withSuccess:YES];
            [self dismissViewController];
        }
        else {
            displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME_SHORT target:self selector:@selector(dismissViewController) userInfo:nil repeats:NO];
        }
    }
    else {
        NSString* error = [result valueForKey:@"Error"];
        
        if ([error length] == 0) {
            if (self.configuration.performEnrollment) {
                error = NSLocalizedString(@"EnrollmentFailed", nil);
            }
            else {
                error = NSLocalizedString(@"VerificationFailed", nil);
            }
        }
        else if ([error isEqualToString:@"LiveDetectionFailed"]) {
            error = NSLocalizedString(@"LiveDetectionFailed", nil);
        }
        else if ([error isEqualToString:@"ChallengeResponseFailed"]) {
            error = NSLocalizedString(@"ChallengeResponseFailed", nil);
        }
        else if ([error isEqualToString:@"NoTemplateAvailable"]) {
            error = NSLocalizedString(@"NoTemplateAvailable", nil);
            executions = 0; // Do not retry!
        }
        else {
            executions = 0; // Do not retry!
        }
        
        [self showMessageLayer:error];
        NSLog(@"TaskResult: %@", result);
        displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME_SHORT target:self selector:@selector(taskFailed) userInfo:nil repeats:NO];
    }
}

- (void)taskFailed {
    [self hideMessageLayer];
    
    executions--;
    if (executions > 0) {
        turnCount = 0;
        return [self start];
    }
    
    [self abortViewController];
}

#pragma mark - BioID Web Service REST calls

- (void)uploadSample:(UIImage *)image withTag:(NSString*)tag {
    if (capturing && uploaded + uploading < recordings) {
        
        // We are already uploading so we should kill the dismiss timer
        [self killDismissTimer];
        
        uploading++;
        sequenceNumber++;
        
        if (uploaded + uploading == recordings) {
            [self hide3DHeadLayer];
            [self showStatusLayer:NSLocalizedString(@"UploadingImages", nil)];
            // Switch off face finder
            faceFinderRunning = false;
        }
        else if (challengeRunning) {
            [self setChallengeAction];
        }
        
        UIImage *grayscale = [self convertImageToGrayScale:image];
        
        NSString *uploadCommand = @"upload";
        if (tag) {
            uploadCommand = [NSString stringWithFormat:@"upload?tag=%@&index=%i&trait=FACE", tag, sequenceNumber];
        }
        
        NSURL *url = [NSURL URLWithString:uploadCommand relativeToURL:self.configuration.bwsInstance];
        NSLog(@"Calling %@", url.absoluteURL);
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.absoluteURL];
        NSString *authorizationHeader = [NSString stringWithFormat:@"Bearer %@", self.configuration.bwsToken];
        
        NSData *pngImage = UIImagePNGRepresentation(grayscale);
//      Save image to the photo library
//      ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
//      [library writeImageDataToSavedPhotosAlbum:pngImage metadata:NULL completionBlock:NULL];
        
        NSLog(@"PNG FileSize: %.f KB", (float)pngImage.length/1024.0f);
        NSString* base64Image = [NSString stringWithFormat:@"data:image/png;base64,%@", [pngImage base64EncodedStringWithOptions:0]];
        NSLog(@"PNG Base64 Size: %.f KB", (float)[base64Image lengthOfBytesUsingEncoding:NSUTF8StringEncoding]/1024.0f);
        
        [request setHTTPMethod:@"POST"];
        [request setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
        [request setHTTPBody:[base64Image dataUsingEncoding:NSUTF8StringEncoding]];
        
        NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:[self sessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
        NSURLSessionDataTask *dataTask = [defaultSession dataTaskWithRequest:request];
        
        if (!uploadTask1) {
            uploadTask1 = dataTask;
            [uploadProgressView1 setProgress:0.0];
            [uploadProgressView1 setHidden:NO];
        }
        else {
            uploadTask2 = dataTask;
            [uploadProgressView2 setProgress:0.0];
            [uploadProgressView2 setHidden:NO];
        }
        
        // Start the connection
        [dataTask resume];
    }
}

- (void)performTask {
    [self stop];
    
    if (self.configuration.performEnrollment)
        [self showMessageLayer:NSLocalizedString(@"Training", nil)];
    else
        [self showMessageLayer:NSLocalizedString(@"Verifying", nil)];
    
    NSURL *url = [NSURL URLWithString:self.configuration.performEnrollment ? @"enroll" : @"verify" relativeToURL:self.configuration.bwsInstance];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.absoluteURL];
    NSString *authorizationHeader = [NSString stringWithFormat:@"Bearer %@", self.configuration.bwsToken];
    
    [request setHTTPMethod:@"GET"];
    [request setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *connectionError) {
        
        if (connectionError) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self reportError:connectionError.localizedDescription withTitle:NSLocalizedString(@"ConnectionError", nil) allowContinue:NO];
            }];
        }
        else {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (statusCode == 200) {
                    NSDictionary* result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    [self biometricTaskExecuted:result];
                }
                else {
                    NSDictionary* result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    [self reportError:[NSString stringWithFormat:NSLocalizedString(@"BWSResult", nil), [NSHTTPURLResponse localizedStringForStatusCode:statusCode], result[@"Message"]] withTitle:NSLocalizedString(@"BiometricTaskFailed", nil) allowContinue:NO];
                }
            }];
        }
    }];
    [dataTask resume];
}

#pragma mark - FaceFinder

- (void)initFaceFinder {
    NSLog(@"Init FaceFinder!");
    // Create the face detector
    detectorOptions = @{ CIDetectorAccuracy: CIDetectorAccuracyLow };
    faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:NULL options:detectorOptions];
}

#pragma mark - Image processing

// Create a UIImage from sample buffer data
- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer orientation:(UIImageOrientation)imageOrientation {
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage scale:1.0 orientation:imageOrientation];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
}

- (UIImage *)scaleAndRotateImage:(UIImage *)image {
    int kMaxResolution = 640;
    
    CGImageRef imgRef = image.CGImage;
    
    CGFloat width = CGImageGetWidth(imgRef);
    CGFloat height = CGImageGetHeight(imgRef);
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    CGRect bounds = CGRectMake(0, 0, width, height);
    if (width > kMaxResolution || height > kMaxResolution) {
        CGFloat ratio = width/height;
        if (ratio > 1) {
            bounds.size.width = kMaxResolution;
            bounds.size.height = bounds.size.width / ratio;
        }
        else {
            bounds.size.height = kMaxResolution;
            bounds.size.width = bounds.size.height * ratio;
        }
    }
    
    CGFloat scaleRatio = bounds.size.width / width;
    CGSize imageSize = CGSizeMake(CGImageGetWidth(imgRef), CGImageGetHeight(imgRef));
    CGFloat boundHeight;
    UIImageOrientation orient = image.imageOrientation;
    
    switch(orient) {
        case UIImageOrientationUp: {
            transform = CGAffineTransformMakeTranslation(imageSize.width, 0.0);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            break;
        }
        case UIImageOrientationDown: {
            transform = CGAffineTransformMakeTranslation(0.0, imageSize.height);
            transform = CGAffineTransformScale(transform, 1.0, -1.0);
            break;
        }
        case UIImageOrientationLeft: {
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeTranslation(imageSize.height, imageSize.width);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
            break;
        }
        case UIImageOrientationRight: {
            boundHeight = bounds.size.height;
            bounds.size.height = bounds.size.width;
            bounds.size.width = boundHeight;
            transform = CGAffineTransformMakeScale(-1.0, 1.0);
            transform = CGAffineTransformRotate(transform, M_PI / 2.0);
            break;
        }
        default:
            [NSException raise:NSInternalInconsistencyException format:@"Invalid image orientation"];
    }
    
    UIGraphicsBeginImageContext(bounds.size);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if (orient == UIImageOrientationRight || orient == UIImageOrientationLeft) {
        CGContextScaleCTM(context, -scaleRatio, scaleRatio);
        CGContextTranslateCTM(context, -height, 0);
    }
    else {
        CGContextScaleCTM(context, scaleRatio, -scaleRatio);
        CGContextTranslateCTM(context, 0, -height);
    }
    
    CGContextConcatCTM(context, transform);
    
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, width, height), imgRef);
    UIImage *imageCopy = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return imageCopy;
}

- (UIImage *)convertImageToGrayScale:(UIImage *)image {
    // Create image rectangle with current image width / height
    CGRect rect = CGRectMake(0.0f, 0.0f, image.size.width, image.size.height);
    // Grayscale color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    // Create bitmap content with current image size and grayscale colorspace
    CGContextRef context = CGBitmapContextCreate(NULL, image.size.width, image.size.height, 8, 0, colorSpace, (CGBitmapInfo)kCGImageAlphaNone);
    
    // Draw image to current context
    CGContextDrawImage(context, rect, [image CGImage]);
    // Create bitmap image info from pixel data n current context
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    // Create a new UImage with grayscale image
    UIImage *grayImage = [UIImage imageWithCGImage:imageRef];
    
    // Release colorspace, context and bitmap info
    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);
    CGImageRelease(imageRef);
    
    // Return the new grayscale image
    return grayImage;
}

- (UIImage *)resizeImageForMotionDetection:(UIImage *)image {
    int resizeWidth;
    int resizeHeight;
    
    if (image.size.width > image.size.height) {
        // Landscape mode
        resizeHeight = 120;
        // Calculate new width according to aspect ratio of original image
        resizeWidth = image.size.width * resizeHeight / image.size.height;
    }
    else {
        // Portrait mode
        resizeWidth = 120;
        // Calculate new height according to aspect ratio of original image
        resizeHeight = image.size.height * resizeWidth / image.size.width;
    }

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(resizeWidth, resizeHeight), YES, 0.0);
    [image drawInRect:CGRectMake(0, 0, resizeWidth, resizeHeight)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resizedImage;
}

// Cut out the template that is used by the motion detection.
-(void)createTemplate:(UIImage *)first {
    UIImage *resizedImage = [self resizeImageForMotionDetection:first];
    UIImage *resizedGrayImage = [self convertImageToGrayScale:resizedImage];
    
    resizeCenterX = resizedGrayImage.size.width / 2;
    resizeCenterY = resizedGrayImage.size.height / 2;
    
    if (resizedGrayImage.size.width > resizedGrayImage.size.height) {
        // Landscape mode
        templateWidth = resizedGrayImage.size.width / 10;
        templateHeight = resizedGrayImage.size.height / 3;
    }
    else {
        // Portrait mode
        templateWidth = resizedImage.size.width / 10 * 4 / 3;
        templateHeight = resizedImage.size.height / 4;
    }
   
    templateXpos = resizeCenterX - templateWidth / 2;
    templateYpos = resizeCenterY - templateHeight / 2;
    
    templateBuffer = nil;
    templateBuffer = malloc(templateWidth * templateHeight);
    
    CFDataRef rawData = CGDataProviderCopyData(CGImageGetDataProvider(resizedGrayImage.CGImage));
    int bytesPerRow = (int)CGImageGetBytesPerRow(resizedGrayImage.CGImage);
    const UInt8* buffer = CFDataGetBytePtr(rawData);

    int counter = 0;
    for (int y = templateYpos; y < templateYpos + templateHeight; y++) {
        for (int x = templateXpos; x < templateXpos + templateWidth; x++) {
            int templatePixel = buffer[x + y * bytesPerRow];
            templateBuffer[counter++] = templatePixel;
        }
    }
   
    // Release
    CFRelease(rawData);
}

// This is the major computing step: Perform a normalized cross-correlation between the template of the first image and each incoming image.
// This algorithm is basically called: "Template Matching" - we use the normalized cross correlation to be independent of lighting images.
// We calculate the correlation of template and image over whole image area.
-(BOOL)motionDetection:(UIImage *)current {
 #ifdef DEBUG
    NSDate *start = [NSDate date];
 #endif
    
    UIImage *resizedImage = [self resizeImageForMotionDetection:current];
    UIImage *resizedGrayImage = [self convertImageToGrayScale:resizedImage];
 
    int bestHitX = 0;
    int bestHitY = 0;
    double maxCorr = 0.0;
    bool triggered = false;
 
    int searchWidth = resizedGrayImage.size.width / 4;
    int searchHeight = resizedGrayImage.size.height / 4;
    
    CFDataRef rawData = CGDataProviderCopyData(CGImageGetDataProvider(resizedGrayImage.CGImage));
    int bytesPerRow = (int)CGImageGetBytesPerRow(resizedGrayImage.CGImage);
    const UInt8* buffer = CFDataGetBytePtr(rawData);
    
    for (int y = resizeCenterY - searchHeight; y <= resizeCenterY + searchHeight - templateHeight; y++) {
        for (int x = resizeCenterX - searchWidth; x <= resizeCenterX + searchWidth - templateWidth; x++) {
            int nominator = 0;
            int denominator = 0;
            int templateIndex = 0;
            
            // Calculate the normalized cross-correlation coefficient for this position
            for (int ty = 0; ty < templateHeight; ty++) {
                int bufferIndex = x + (y + ty) * bytesPerRow;
                for (int tx = 0; tx < templateWidth; tx++) {
                    int imagePixel = buffer[bufferIndex++];
                    nominator += templateBuffer[templateIndex++] * imagePixel;
                    denominator += imagePixel * imagePixel;
                }
            }
        
            // The NCC coefficient is then (watch out for division-by-zero errors for bure black images)
            double ncc = 0.0;
            if (denominator > 0) {
                ncc = (double)nominator * (double)nominator / (double)denominator;
            }
            // Is it higher that what we had before?
            if (ncc > maxCorr) {
                maxCorr = ncc;
                bestHitX = x;
                bestHitY = y;
            }
        }
    }
    
    // Now the most similar position of the template is (bestHitX, bestHitY). Calculate the difference from the origin
    int distX = bestHitX - templateXpos;
    int distY = bestHitY - templateYpos;

    double movementDiff = sqrt(distX * distX + distY * distY);
    
    // The maximum movement possible is a complete shift into one of the corners, i.e.
    int maxDistX = searchWidth - templateWidth / 2;
    int maxDistY = searchHeight - templateHeight / 2;
    double maximumMovement = sqrt((double)maxDistX * maxDistX + (double)maxDistY * maxDistY);
    
    // The percentage of the detected movement is therefore
    double movementPercentage = movementDiff / maximumMovement * 100.0;
    
    if (movementPercentage > 100.0) {
        movementPercentage = 100.0;
    }
 
#ifdef DEBUG
    NSDate *stop = [NSDate date];
    NSTimeInterval execution = [stop timeIntervalSinceDate:start];
    NSString *info = [NSString stringWithFormat:@"Time: %.3fs - Movement: %.1f", execution, movementPercentage];
    NSMutableAttributedString *infoString =[[NSMutableAttributedString alloc] initWithString:@""];
    
    if (info != NULL) {
        infoString = [[NSMutableAttributedString alloc] initWithString:info];
        [infoString addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:(NSRange){0, infoString.length}];
        [infoString addAttribute:NSFontAttributeName value:[UIFont fontWithName:BIOID_FONT size:15] range:[infoString.string rangeOfString:infoString.string]];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        debugLabel.attributedText = infoString;
        [debugLabel setNeedsDisplay];
    });
#endif
    
    // Trigger if movementPercentage is above threshold (default: when 15% of the maximum movement is exceeded)
    if (movementPercentage > MIN_MOVEMENT_PERCENTAGE)  {
        triggered = true;
    }
    
    // Release
    CFRelease(rawData);
    
    return triggered;
}

#pragma mark - AVCapture

- (BOOL)setupAVCapture {
    NSLog(@"Initialize camera!");
    NSError *error = nil;
    
    // Get front camera
    captureDevice = [self frontCamera];
    
    // setting up white balance
    if ([captureDevice isWhiteBalanceModeSupported: AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
      if ([captureDevice lockForConfiguration:nil]) {
          [captureDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeAutoWhiteBalance];
          [captureDevice unlockForConfiguration];
      }
    }
    
    // Add the device to the session.
    AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:&error];
    if(error) {
        return NO;
    }
    
    captureSession = [[AVCaptureSession alloc] init];
    [captureSession beginConfiguration];
    
    if([captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    }
    [captureSession addInput:input];
    
    // Create the output for the capture session.
    videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [videoDataOutput setVideoSettings:rgbOutputSettings];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    
    if ([captureSession canAddOutput:videoDataOutput]) {
        [captureSession addOutput:videoDataOutput];
    }
    
    previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    CALayer *rootLayer = [previewView layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:previewLayer];
    [captureSession commitConfiguration];
    
    return YES;
}

- (void)teardownAVCapture {
    [previewLayer removeFromSuperlayer];
}

- (AVCaptureDevice *)frontCamera {
    NSLog(@"Get front camera!");
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if ([device position] == AVCaptureDevicePositionFront) {
            return device;
        }
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

#pragma mark - Device Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (void)viewWillLayoutSubviews {
    previewLayer.frame = self.view.bounds;
    previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
}

-(void)orientationChanged:(NSNotification *)notification {
    [self setLayers:[[UIDevice currentDevice] orientation]];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Timers
    
- (void)startWaitForCameraTimer {
    cameraTimer = [NSTimer scheduledTimerWithTimeInterval:WAIT_FOR_CAMERA_ADJUSTMENT target:self selector:@selector(killWaitForCameraTimer) userInfo:nil repeats:NO];
}
    
- (void)killWaitForCameraTimer {
    if (cameraTimer && [cameraTimer isValid]) {
        NSLog(@"Kill camera Timer");
        [cameraTimer invalidate];
        faceFinderRunning = true;
    }
    cameraTimer = nil;
}

- (void)startDismissTimer:(NSString *)message {
    [self killDismissTimer];
    NSLog(@"Starting dismiss timer");
    killTimer = [NSTimer scheduledTimerWithTimeInterval:INACTIVITY_TIMEOUT target:self selector:@selector(dismissTimerMethod:) userInfo:message repeats:NO];
}

- (void)killDismissTimer {
    if (killTimer && [killTimer isValid]) {
        NSLog(@"Stopping dismiss timer");
        [killTimer invalidate];
    }
    killTimer = nil;
}

- (void)dismissTimerMethod:(NSTimer *)timer {
    NSLog(@"Dismiss timer fired!");
    NSString *msg = timer.userInfo;
    [self stop];
    [self showMessageLayer:msg];
    if(self.callback) {
        [self.callback biometricTaskFinished:self.configuration withSuccess:NO];
    }
    
    displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME target:self selector:@selector(abortViewController) userInfo:nil repeats:NO];
}

- (void)startTriggerTimer {
    triggerTimer = [NSTimer scheduledTimerWithTimeInterval:TRIGGER_INTERVAL target:self selector:@selector(triggerTimerMethod) userInfo:nil repeats:NO];
    NSLog(@"Start TriggerTimer");
}

- (void)triggerTimerMethod {
    NSLog(@"TriggerTimer captureTriggered");
    captureTriggered = true;
}

- (void)killTriggerTimer {
    NSLog(@"Kill TriggerTimer");
    if (triggerTimer && [triggerTimer isValid])
        [triggerTimer invalidate];
    triggerTimer = nil;
}

- (void)startChallengeResponseTimer {
    challengeWait = true;
    challengeResponseTimer = [NSTimer scheduledTimerWithTimeInterval:CHALLENGE_RESPONSE_INTERVAL target:self selector:@selector(killChallengeResponseTimer) userInfo:nil repeats:NO];
}

- (void)killChallengeResponseTimer {
    NSLog(@"Kill challenge response timer");
    challengeWait = false;
    if (challengeResponseTimer && [challengeResponseTimer isValid]) {
        [challengeResponseTimer invalidate];
    }
    challengeResponseTimer = nil;
}

#pragma mark - SceneKit

- (void)createSceneView {
    // Create a new scene
    SCNScene *headScene = [SCNScene sceneNamed:@"art.scnassets/3DHead.dae"];
    
    // Create and add a camera to the scene
    SCNNode *cameraNode = [SCNNode node];
    cameraNode.camera = [SCNCamera camera];
    
    // Place the camera
    cameraNode.position = SCNVector3Make(-0.05, 0.15, 0.7);
    [headScene.rootNode addChildNode:cameraNode];
    
    // Retrieve the head node
    headNode = nil;
    headNode = [headScene.rootNode childNodeWithName:@"BioID-Head" recursively:YES];
    
    // Set the scene to the view
    sceneView.scene = nil;
    sceneView.scene = headScene;
    
    // Configure the background color
    sceneView.backgroundColor = [UIColor darkGrayColor]; // or use clearColor
}

- (void)createActionForLiveDetection {
    [self createSceneView];
    
    // Sequence
    SCNAction *sequenceAction = nil;
    
    // Pause action
    SCNAction *pauseAction = [SCNAction waitForDuration:0.0];
   
    // Generates random number between 1 to 100
    int randDirection = arc4random_uniform(100)+1;
        
    if (randDirection <= 50) {
            
        // Left rotation and back to center position
        SCNAction *centerToLeftAction = [SCNAction rotateByX:0 y:-0.5 z:0 duration:0.7];
        SCNAction *leftToCenterAction = [SCNAction rotateByX:0 y:0.5 z:0 duration:0.7];
        
        // Right rotation and back to center position
        SCNAction *centerToRightAction = [SCNAction rotateByX:0 y:0.5 z:0 duration:0.7];
        SCNAction *rightToCenterAction = [SCNAction rotateByX:0 y:-0.5 z:0 duration:0.7];
            
        // Complete sequence
        sequenceAction = [SCNAction repeatActionForever:[SCNAction sequence:@[centerToLeftAction, pauseAction, leftToCenterAction,
                                                                              centerToRightAction, pauseAction, rightToCenterAction]]];
    }
    else {
        // Up rotation and back to center position
        SCNAction *centerToUpAction = [SCNAction rotateByX:-0.5 y:0 z:0 duration:0.7];
        SCNAction *upToCenterAction = [SCNAction rotateByX:0.5 y:0 z:0 duration:0.7];
        
        // Down rotation and back to center position
        SCNAction *centerToDownAction = [SCNAction rotateByX:0.5 y:0 z:0 duration:0.7];
        SCNAction *downToCenterAction = [SCNAction rotateByX:-0.5 y:0 z:0 duration:0.7];
            
        // Complete sequence
        sequenceAction = [SCNAction repeatActionForever:[SCNAction sequence:@[centerToUpAction, pauseAction, upToCenterAction,
                                                                              centerToDownAction, pauseAction, downToCenterAction]]];
    }
    
    [headNode runAction:sequenceAction];
}

- (void)createActionForChallenge {
    [self createSceneView];
    
    challengeStep = 0;
    challengeSCNActions = nil;
    challengeSCNActions = [[NSMutableArray alloc] init];
    
    // Create sequence for 3D Head
    for (id direction in currentChallenge) {
        if([direction isEqualToString:@"up"]) {
            [challengeSCNActions addObject:[SCNAction sequence:@[[SCNAction rotateByX:-0.5 y:0 z:0 duration:1.0]]]];
        }
        else if([direction isEqualToString:@"down"]) {
            [challengeSCNActions addObject:[SCNAction sequence:@[[SCNAction rotateByX:0.5 y:0 z:0 duration:1.0]]]];
        }
        else if([direction isEqualToString:@"left"]) {
            [challengeSCNActions addObject:[SCNAction sequence:@[[SCNAction rotateByX:0 y:-0.5 z:0 duration:1.0]]]];
        }
        else if([direction isEqualToString:@"right"]) {
            [challengeSCNActions addObject:[SCNAction sequence:@[[SCNAction rotateByX:0 y:0.5 z:0 duration:1.0]]]];
        }
        NSLog(@"%@", direction);
    }
}

- (void)setChallengeAction {
    // Give the user some time to react!
    [self startChallengeResponseTimer];
    
    if (challengeStep < [currentChallenge count]) {
        // Show next direction
        SCNAction *sequenceAction = [SCNAction sequence:@[[challengeSCNActions objectAtIndex:challengeStep]]];
        [headNode runAction:sequenceAction];
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self show3DHeadLayer];
        });
    }
}

#pragma mark - Create and update layers

- (void)createLayers {
    UIBlurEffect *effectDark = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    viewWithBlurredBackground = [[UIVisualEffectView alloc] initWithEffect:effectDark];
    [viewWithBlurredBackground setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
    [viewWithBlurredBackground setHidden:YES];
    
    sceneView = [[SCNView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
    [sceneView setHidden:YES];
    [sceneView setAlpha:0.85];
    [self.view addSubview:sceneView];
    
    messageLabel = [[UILabel alloc] init];
    [messageLabel setTextAlignment:NSTextAlignmentCenter];
    [messageLabel setNumberOfLines:3];
    [messageLabel setFrame:CGRectMake(0, 0, viewWithBlurredBackground.frame.size.width, viewWithBlurredBackground.frame.size.height)];
    
    [viewWithBlurredBackground addSubview:messageLabel];
    [self.view addSubview:viewWithBlurredBackground];
    
    statusViewBlurred = [[UIVisualEffectView alloc] initWithEffect:effectDark];
    [statusViewBlurred setBounds:CGRectMake(0, 0, 300, 70)];
    [statusViewBlurred setHidden:YES];
    
    statusLabel = [[UILabel alloc] init];
    [statusLabel setTextAlignment:NSTextAlignmentCenter];
    [statusLabel setFrame:CGRectMake(0, 0, statusViewBlurred.frame.size.width, statusViewBlurred.frame.size.height)];
    
    [statusViewBlurred addSubview:statusLabel];
    [self.view addSubview:statusViewBlurred];
    
    uploadProgressView1 = [[UIProgressView alloc] init];
    if (self.view.bounds.size.height > self.view.bounds.size.width) {
        [uploadProgressView1 setFrame:CGRectMake(20, self.view.bounds.size.height-50, self.view.bounds.size.width-40, 30)];
    }
    else {
        [uploadProgressView1 setFrame:CGRectMake(20, self.view.bounds.size.width-50, self.view.bounds.size.height-40, 30)];
    }
    [uploadProgressView1 setHidden:YES];
    [self.view addSubview:uploadProgressView1];
    
    uploadProgressView2 = [[UIProgressView alloc] init];
    if (self.view.bounds.size.height > self.view.bounds.size.width) {
        [uploadProgressView2 setFrame:CGRectMake(20, self.view.bounds.size.height-30, self.view.bounds.size.width-40, 30)];
    }
    else {
        [uploadProgressView2 setFrame:CGRectMake(20, self.view.bounds.size.width-30, self.view.bounds.size.height-40, 30)];
    }
    [uploadProgressView2 setHidden:YES];
    [self.view addSubview:uploadProgressView2];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    alertView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    alertView.layer.cornerRadius = 5;
    alertView.layer.masksToBounds = YES;
    [alertView setHidden:YES];
    [alertView setCenter:self.view.center];
    [self.view addSubview:alertView];
    
#ifdef DEBUG
    debugLabel = [[UILabel alloc] init];
    [debugLabel setTextAlignment:NSTextAlignmentCenter];
    [debugLabel setBounds:CGRectMake(0, 0, 375, 20)];
    [debugLabel setBackgroundColor:[UIColor blackColor]];
    [self.view addSubview:debugLabel];
#endif
}

- (void)setLayers:(UIDeviceOrientation)deviceOrientation {
    [viewWithBlurredBackground setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
    
    switch (deviceOrientation) {
        case UIDeviceOrientationPortrait: {
            [statusViewBlurred setCenter:CGPointMake(self.view.bounds.size.width/2, 70)];
            [statusViewBlurred setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [messageLabel setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
            [messageLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [uploadProgressView1 setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-50)];
            [uploadProgressView1 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [uploadProgressView2 setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-30)];
            [uploadProgressView2 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [debugLabel setCenter:CGPointMake(self.view.bounds.size.width/2, 10)];
            [debugLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [alertView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [sceneView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [sceneView setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
            break;
        }
        case UIDeviceOrientationPortraitUpsideDown: {
            [statusViewBlurred setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-70)];
            [statusViewBlurred setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [messageLabel setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
            [messageLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            // Rotate 180 degree
            [uploadProgressView1 setCenter:CGPointMake(self.view.bounds.size.width/2, 50)];
            [uploadProgressView1 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [uploadProgressView2 setCenter:CGPointMake(self.view.bounds.size.width/2, 30)];
            [uploadProgressView2 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [debugLabel setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-10)];
            [debugLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [alertView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [sceneView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [sceneView setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
            break;
        }
        case UIDeviceOrientationLandscapeLeft: {
            [statusViewBlurred setCenter:CGPointMake(self.view.bounds.size.width-40, self.view.bounds.size.height/2)];
            [statusViewBlurred setTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
            [messageLabel setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
            [messageLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
            [uploadProgressView1 setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-50)];
            [uploadProgressView1 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [uploadProgressView2 setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-30)];
            [uploadProgressView2 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [debugLabel setCenter:CGPointMake(self.view.bounds.size.width-10, self.view.bounds.size.height/2)];
            [debugLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
            [alertView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
            [sceneView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
            [sceneView setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
            break;
        }
        case UIDeviceOrientationLandscapeRight: {
            [statusViewBlurred setCenter:CGPointMake(40, self.view.bounds.size.height/2)];
            [statusViewBlurred setTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
            [messageLabel setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
            [messageLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
            // Rotate 180 degree
            [uploadProgressView1 setCenter:CGPointMake(self.view.bounds.size.width/2, 50)];
            [uploadProgressView1 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [uploadProgressView2 setCenter:CGPointMake(self.view.bounds.size.width/2, 30)];
            [uploadProgressView2 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
            [debugLabel setCenter:CGPointMake(10, self.view.bounds.size.height/2)];
            [debugLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
            [alertView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
            [sceneView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
            [sceneView setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
            break;
        }
        default: {
            // Show UIDeviceOrientationPortrait!
            [statusViewBlurred setCenter:CGPointMake(self.view.bounds.size.width/2, 70)];
            [statusViewBlurred setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [messageLabel setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)];
            [messageLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [uploadProgressView1 setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-50)];
            [uploadProgressView1 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [uploadProgressView2 setCenter:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height-30)];
            [uploadProgressView2 setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [debugLabel setCenter:CGPointMake(self.view.bounds.size.width/2, 10)];
            [debugLabel setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [alertView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [sceneView setTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
            [sceneView setFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
            break;
        }
    }
    [self.view setNeedsLayout];
}

#pragma mark - Display layers

- (void)showStatusLayer:(NSString *)status {
    NSMutableAttributedString *statusString =[[NSMutableAttributedString alloc] initWithString:@""];
    
    if (status) {
        statusString = [[NSMutableAttributedString alloc] initWithString:status];
        [statusString addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:(NSRange){0, statusString.length}];
        [statusString addAttribute:NSFontAttributeName value:[UIFont fontWithName:BIOID_FONT size:20] range:[statusString.string rangeOfString:statusString.string]];
    }

   [statusLabel setAttributedText:statusString];
   [statusLabel setNeedsDisplay];
   [statusViewBlurred setHidden:NO];
}

- (void)hideStatusLayer {
    [statusViewBlurred setHidden:YES];
}

- (void)show3DHeadLayer {
    [sceneView setHidden:NO];
}

- (void) hide3DHeadLayer {
    [sceneView setHidden:YES];
}

- (void)showMessageLayer:(NSString *)message {
    [self hideStatusLayer];
    [self hide3DHeadLayer];
    
    NSMutableAttributedString *messageString = [[NSMutableAttributedString alloc] initWithString:message];
    [messageString addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:(NSRange){0, messageString.length}];
    [messageString addAttribute:NSFontAttributeName value:[UIFont fontWithName:BIOID_FONT size:20] range:[messageString.string rangeOfString:messageString.string]];
    
    [messageLabel setAttributedText:messageString];
    [messageLabel setNeedsDisplay];
    [viewWithBlurredBackground setHidden:NO];
}

- (void)hideMessageLayer {
    [viewWithBlurredBackground setHidden:YES];
}

#pragma mark - URLSessions

- (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:0 diskPath:nil];
    return config;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    
    completionHandler(NSURLSessionResponseAllow);
    
    NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    uploading--;
    if (statusCode != 200) {
        NSLog(@"Upload failed with status code: %ld", (long)statusCode);
        [self stop];
        [self reportError:[NSString stringWithFormat:NSLocalizedString(@"ReportedError", nil), [NSHTTPURLResponse localizedStringForStatusCode:statusCode]] withTitle:NSLocalizedString(@"ImageUploadError", nil) allowContinue:NO];
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // Ensure that a dismiss-timer is running
    [self startDismissTimer:NSLocalizedString(@"NoMotionDetected", nil)];
    
    NSDictionary* uploadResult = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    BOOL accepted = [[uploadResult valueForKey:@"Accepted"] boolValue];
    if (accepted) {
        NSLog(@"Upload accepted");
        uploaded++;
    }
    else {
        // NoFaceFound or MultipleFacesFound
        NSLog(@"UploadResult: %@", uploadResult);
        NSString *error = [uploadResult valueForKey:@"Error"];
        NSString *msg = NSLocalizedString(@"ImageDeclined", nil);
        if([error isEqualToString:@"NoFaceFound"]) {
            msg = NSLocalizedString(@"NoFaceFound", nil);
            noFaceFound++;
        }
        else if([error isEqualToString:@"MultipleFacesFound"]) {
            msg = NSLocalizedString(@"MultipleFacesFound", nil);
            noFaceFound++; // Multiple faces are not allowed!
        }

        [self stop]; 
        [self showMessageLayer:msg];
        
        if (currentChallenge && uploaded > 0) {
            displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME_SHORT target:self selector:@selector(performTask) userInfo:nil repeats:NO];
        }
        else if (noFaceFound < DEFAULT_MAX_NOFACE_FOUND) {
            displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME_SHORT target:self selector:@selector(start) userInfo:nil repeats:NO];
        }
        else {
            displayTimer = [NSTimer scheduledTimerWithTimeInterval:MESSAGE_DISPLAY_TIME_SHORT target:self selector:@selector(dismissViewController) userInfo:nil repeats:NO];
        }
        
        if (dataTask == uploadTask1) {
            uploadTask1 = nil;
        }
        else if (dataTask == uploadTask2) {
            uploadTask2 = nil;
        }
    }
    
    if (uploaded >= recordings && uploading == 0) {
        if(!self.configuration.performEnrollment || turnCount >= requiredTurns) {
            uploadTask1 = nil;
            uploadTask2 = nil;
            // Go for biometric task
            [self performTask];
        }
        else {
            // User shall record more images in a different position
            turnCount++;
            noFaceFound = 0;
            [self turnPosition];
            [self createActionForLiveDetection];
        }
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    if (task == uploadTask1)  {
        [uploadProgressView1 setProgress: (double)totalBytesSent / (double)totalBytesExpectedToSend animated:YES];
        NSLog(@"UploadConnection 1: %li of %li", (long)totalBytesSent, (long)totalBytesExpectedToSend);
    }
    else if (task == uploadTask2) {
        [uploadProgressView2 setProgress: (double)totalBytesSent / (double)totalBytesExpectedToSend animated:YES];
        NSLog(@"UploadConnection 2: %li of %li", (long)totalBytesSent, (long)totalBytesExpectedToSend);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"Connection error: %@", error.localizedDescription);
        [self stop];
        [self reportError:error.localizedDescription withTitle:NSLocalizedString(@"ConnectionError", nil) allowContinue:NO];
    }
}

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    if (error) {
        NSLog(@"Connection error: %@", error.localizedDescription);
        [self stop];
        [self reportError:error.localizedDescription withTitle:NSLocalizedString(@"ConnectionError", nil) allowContinue:NO];
    }
    [session finishTasksAndInvalidate];
}

#pragma mark - Base64Url Decoder

- (NSString *)base64UrlDecode:(NSString *)input {
    NSArray *token = [input componentsSeparatedByString:@"."];
    NSString *base64Url = [token objectAtIndex:1];
    
    base64Url = [base64Url stringByReplacingOccurrencesOfString:@"-" withString:@"+"]; // 62nd char of encoding
    base64Url = [base64Url stringByReplacingOccurrencesOfString:@"_" withString:@"/"]; // 63rd char of encoding
    
    // Pad with trailing '='s
    NSUInteger paddedLength = base64Url.length + (4 - (base64Url.length % 4)) % 4;
    NSString *correctBase64String = [base64Url stringByPaddingToLength:paddedLength withString:@"=" startingAtIndex:0];
    
    NSData *nsdataFromBase64String = [[NSData alloc] initWithBase64EncodedString:correctBase64String options:0];
    NSString *base64Decoded = [[NSString alloc] initWithData:nsdataFromBase64String encoding:NSUTF8StringEncoding];
    NSLog(@"Decoded token value: %@", base64Decoded);
    
    return base64Decoded;
}

#pragma mark - Custom AlertView

- (void)showAlertView:(NSString *)title message:(NSString *)message continueAction:(BOOL)continueAction abortAction:(BOOL)abortAction {
    int alertViewWidth = 270;
    int alertViewHeight = 150;
    int titleYPos = 20;
    int titleHeight = 20;
    int offsetX = 10;
    int offsetY = 15;
    int buttonHeight = 45;
    
    // Cleanup alertView and remove UILabels and UIButtons
    for (UIView *subview in alertView.subviews) {
        if ([subview isKindOfClass:[UILabel class]] || [subview isKindOfClass:[UIButton class]]) {
            [subview removeFromSuperview];
        }
    }
    
    UILabel *motLabel = [[UILabel alloc] init];
    [motLabel setTextColor:[UIColor whiteColor]];
    [motLabel setFont:[UIFont fontWithName:BIOID_FONT size:14]];
    [motLabel setText:message];
    [motLabel setNumberOfLines:0];
    [motLabel setTextAlignment:NSTextAlignmentCenter];
    
    // Calculate size of message text
    CGRect labelFrame = CGRectMake(offsetX, titleYPos+titleHeight+offsetY, alertViewWidth-offsetX, 0);
    labelFrame.size = [motLabel sizeThatFits:CGSizeMake(alertViewWidth-2*offsetX, 190)];
    if (labelFrame.size.height > 190) labelFrame.size.height = 190;
    [motLabel setFrame:labelFrame];
    
    // Resize alertView for the message text
    alertViewHeight = titleYPos+titleHeight+motLabel.frame.size.height+buttonHeight+offsetY*2;
    [alertView setBounds:CGRectMake(0, 0, alertViewWidth, alertViewHeight)];
    [alertView addSubview:motLabel];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    [titleLabel setTextColor:[UIColor whiteColor]];
    [titleLabel setFont:[UIFont fontWithName:BIOID_FONT size:18]];
    [titleLabel setText:title];
    [titleLabel setTextAlignment:NSTextAlignmentCenter];
    [titleLabel setFrame:CGRectMake(0, titleYPos, alertViewWidth, titleHeight)];
    [alertView addSubview:titleLabel];
    
    if (!abortAction || !continueAction) {
        // We have only one button
        UIButton *actionButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [[actionButton titleLabel] setFont:[UIFont fontWithName:BIOID_FONT size:18]];
        [[actionButton layer] setBorderWidth:1.0f];
        [[actionButton layer] setBorderColor:[UIColor lightGrayColor].CGColor];
        [actionButton setClipsToBounds:YES];
        [actionButton setFrame:CGRectMake(-1, alertViewHeight-buttonHeight, alertViewWidth+2, buttonHeight+1)];
        [actionButton setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
        [actionButton setTag:1];
        if (abortAction) {
            [actionButton setTitle:NSLocalizedString(@"Abort", nil) forState:UIControlStateNormal];
            [actionButton setTag:2];
        }
        [actionButton addTarget:self action:@selector(actionClicked:) forControlEvents:UIControlEventTouchUpInside];
        [alertView addSubview:actionButton];
    }
    else {
        // Ohterwise we have 2 buttons
        UIButton *abortButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [[abortButton titleLabel] setFont:[UIFont fontWithName:BIOID_FONT size:18]];
        [[abortButton layer] setBorderWidth:1.0f];
        [[abortButton layer] setBorderColor:[UIColor lightGrayColor].CGColor];
        [abortButton setClipsToBounds:YES];
        [abortButton setFrame:CGRectMake(-1, alertViewHeight-buttonHeight, alertViewWidth/2+1, buttonHeight+1)];
        [abortButton setTitle:NSLocalizedString(@"Abort", nil) forState:UIControlStateNormal];
        [abortButton setTag:2];
        [abortButton addTarget:self action:@selector(actionClicked:) forControlEvents:UIControlEventTouchUpInside];
        [alertView addSubview:abortButton];
        
        UIButton *continueButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [[continueButton titleLabel] setFont:[UIFont fontWithName:BIOID_FONT size:18]];
        [[continueButton layer] setBorderWidth:1.0f];
        [[continueButton layer] setBorderColor:[UIColor lightGrayColor].CGColor];
        [continueButton setClipsToBounds:YES];
        [continueButton setFrame:CGRectMake(alertViewWidth/2-1, alertViewHeight-buttonHeight, alertViewWidth/2+2, buttonHeight+1)];
        [continueButton setTitle:NSLocalizedString(@"Continue", nil) forState:UIControlStateNormal];
        [continueButton addTarget:self action:@selector(actionClicked:) forControlEvents:UIControlEventTouchUpInside];
        [alertView addSubview:continueButton];
    }
    
    [alertView setCenter:self.view.center];
    [alertView setHidden:NO];
}

- (void)reportError:(NSString *)message withTitle:(NSString *)title allowContinue:(BOOL)allowContinue {
    if(![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reportError:message withTitle:title allowContinue:allowContinue];
        });
        return;
    }
    
    [self showAlertView:title message:message continueAction:allowContinue abortAction:TRUE ];
}

// Action from alertView
- (void)actionClicked:(UIButton*) sender {
    [alertView setHidden:YES];
    switch(sender.tag) {
        case 1: {
            // Enrollment prodecure - Contiune
            [self start];
            break;
        }
        case 2: {
            // Reporting Error - Abort
            [self abortViewController];
            break;
        }
        default:
            // Continue with no action
            break;
    }
}

@end
