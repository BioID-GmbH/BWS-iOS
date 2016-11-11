//
//  CaptureViewController.h
//  BioIDSample
//
//  Copyright (c) 2015 BioID. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <SceneKit/SceneKit.h>
#import <ImageIO/ImageIO.h>
#import "CaptureConfiguration.h"

// BioID Web Service (BWS) TokenTask flags
typedef enum {
    TokenTaskVerify              = 0,
    TokenTaskEnroll              = 0x20,
    TokenTaskMaxTriesMask        = 0x0F,
    TokenTaskLiveDetection       = 0x100,
    TokenTaskChallengeResponse   = 0x200,
    TokenTaskAutoEnroll          = 0x1000
} TokenTask;

@class CIDetector;

@interface CaptureViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate, NSURLSessionDataDelegate>
{
@private
    // Visual effect views
    UIVisualEffectView *viewWithBlurredBackground;
    UIVisualEffectView *statusViewBlurred;
    UIVisualEffectView *alertView;
    
    // Progress views
    UIProgressView *uploadProgressView1;
    UIProgressView *uploadProgressView2;
    
    // Labels for displaying messages
    UILabel *messageLabel;
    UILabel *statusLabel;
    UILabel *debugLabel;
    
    // SceneView for 3D head
    SCNView *sceneView;
 
    // NSURLSessionDataTask for uploads
    NSURLSessionDataTask *uploadTask1;
    NSURLSessionDataTask *uploadTask2;
    
    // Capture device & video output
    BOOL cameraAccess;
    AVCaptureDevice *captureDevice;
    AVCaptureVideoPreviewLayer *previewLayer;
    AVCaptureVideoDataOutput *videoDataOutput;
    dispatch_queue_t videoDataOutputQueue;
    
    // FaceDetector
    CIDetector *faceDetector;
    NSDictionary *detectorOptions;

    // Timers
    NSTimer *cameraTimer;
    NSTimer *killTimer;
    NSTimer *triggerTimer;
    NSTimer *displayTimer;
    NSTimer *challengeResponseTimer;

    // Reference image for motion detection
    UIImage *referenceImage;
    
    // Set of challenges (challenge response)
    NSArray *challenges;
    // current challenge
    NSArray *currentChallenge;
    
    // Current used token task (BWS)
    NSInteger taskFlags;
    
    // Actions for 3D head
    NSMutableArray *challengeSCNActions;
    
    // 3D head node
    SCNNode *headNode;
    
    // Maximum tries until failure is reported
    int maxTries;
    // Counter for tries to perform biometric task
    int executions;
    // Counter for 'No face found'
    int noFaceFound;
    // Number of required recordings
    int recordings;
    // Counter for uploaded images
    int uploaded;
    // Counter for uploading images
    int uploading;
    // Numbering to ensure order of upload samples
    int sequenceNumber;
    // Counter for continuous found faces
    int continuousFoundFaces;

    // For start capturing
    BOOL faceFinderRunning;
    BOOL captureTriggered;
    BOOL capturing;
   
    // For enrollment
    int turnCount;
    int requiredTurns;
    
    // For challenge response
    int challengeStep;
    BOOL challengeRunning;
    BOOL challengeWait;
}

@property (weak, nonatomic) IBOutlet UIView *previewView;
// configuration settings and callback provided by the caller
@property (nonatomic) CaptureConfiguration *configuration;
@property (nonatomic) id<CaptureDelegate> callback;

@end
