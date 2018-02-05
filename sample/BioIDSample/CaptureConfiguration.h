//
//  CaptureConfiguration.h
//  BioIDSample
//
//  Copyright (c) 2015 BioID. All rights reserved.
//

#import <Foundation/Foundation.h>

#if ! DEBUG
    #define NSLog(...) /* suppress NSLog when in release mode */
#endif

@interface CaptureConfiguration : NSObject

@property (nonatomic, readonly) NSString *bwsToken;
@property (nonatomic, readonly) BOOL performEnrollment;
@property (nonatomic, readonly) NSURL *bwsInstance;
@property (nonatomic, readonly) NSString *traits;
@property (nonatomic, readonly) BOOL challenge;

-(id)initForEnrollment:(NSString *)traits;
-(id)initForVerification:(BOOL)enableChallenge withTraits:(NSString *)traits;
-(void)ensureToken:(void (^)(NSError *))callbackBlock;

@end

@protocol CaptureDelegate

- (void)biometricTaskFinished:(CaptureConfiguration*)data withSuccess:(BOOL)success;

@end
