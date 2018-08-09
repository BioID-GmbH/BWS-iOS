//
//  CaptureConfiguration.m
//  BioIDSample
//
//  Copyright (c) 2015 BioID. All rights reserved.
//

#import "CaptureConfiguration.h"

#error You need to put your own credentials here. Go to https://bwsportal.bioid.com/register if you don't have a trial instance of BWS!
#warning Don't forget these credentials should come from your server in production systems! Only for quickly checking how this code works you put the credentials here!
NSString * const BWS_INSTANCE_NAME = @"";
NSString * const CLIENT_APP_ID = @"";
NSString * const CLIENT_APP_SECRET = @"";
NSString * const BCID = @"";

@implementation CaptureConfiguration

// Default init for verification and without challenge
-(id)init {
    if (self = [super init]) {
        _bwsToken = nil;
        _performEnrollment = false;
        _bwsInstance = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.bioid.com/extension/", BWS_INSTANCE_NAME]];
        _challenge = false;
    }
    return self;
}

-(id)initForEnrollment:(NSString *) traits {
    if (self = [super init]) {
        _bwsToken = nil;
        _performEnrollment = true;
        _bwsInstance = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.bioid.com/extension/", BWS_INSTANCE_NAME]];
        _traits = traits;
        if (traits.length == 0) {
            _traits = @"Face,Periocular"; // this is the default value of BioID Web Service (BWS)
        }
        // CHALLENGE RESPONSE SHOULD BE USED ONLY FOR VERIFICATION
        _challenge = false;
    }
    return self;
}

-(id)initForVerification:(BOOL)enableChallenge withTraits:(NSString *) traits {
    if (self = [super init]) {
        _bwsToken = nil;
        _performEnrollment = false;
        _bwsInstance = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.bioid.com/extension/", BWS_INSTANCE_NAME]];
        _traits = traits;
        if (traits.length == 0) {
            _traits = @"Face,Periocular"; // this is the default value of BioID Web Service (BWS)
        }
        _challenge = enableChallenge;
    }
    return self;
}

-(void)ensureToken:(void (^)(NSError *))callbackBlock {
    if(_bwsToken.length > 0) {
        callbackBlock(nil);
        return;
    }

    if(_performEnrollment) {
        [self fetchBWSToken:@"enroll" onCompletion:^(NSString *token, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_bwsToken = token;
                callbackBlock(error);
            });
        }];
    }
    else {
        [self fetchBWSToken:@"verify" onCompletion:^(NSString *token, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_bwsToken = token;
                callbackBlock(error);
            });
        }];
    }
}

- (void)fetchBWSToken:(NSString*) bwsTask onCompletion:(void (^)(NSString *, NSError *))callbackBlock {
    // Create BWS Extension URL
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@.bioid.com/extension/token?id=%@&bcid=%@&task=%@&challenge=%@&traits=%@", BWS_INSTANCE_NAME, CLIENT_APP_ID, BCID, bwsTask, _challenge ? @"true" : @"false", _traits]];
    NSLog(@"URL %@", [url absoluteString]);
    
    // Create the authentication header for Basic Authentication
    NSData *authentication = [[NSString stringWithFormat:@"%@:%@", CLIENT_APP_ID, CLIENT_APP_SECRET] dataUsingEncoding:NSASCIIStringEncoding];
    NSString *base64String = [authentication base64EncodedStringWithOptions:0];
    NSString *authorizationHeader = [NSString stringWithFormat:@"Basic %@", base64String];
    
    // Create single request object for a series of URL load requests
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    
    // Request a BWS token to be used for authorization for BWS Extension Web API
    [request setValue:authorizationHeader forHTTPHeaderField:@"Authorization"];
    
    NSLog(@"Get BWS token %@", request);
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *connectionError) {
        if (connectionError) {
            NSLog(@"Connection error: %@", connectionError.localizedDescription);
            callbackBlock(nil, connectionError);
        }
        else {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode == 200) {
                NSLog(@"Get BWS token");
                NSString *bwsToken = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
                callbackBlock(bwsToken, nil);
            }
            else {
                NSLog(@"Get BWS token failed with status code: %ld", (long)statusCode);
                callbackBlock(nil, [[NSError alloc] initWithDomain:@"BioIDServiceError" code:statusCode userInfo:nil]);
            }
        }
    }];    
    [dataTask resume];
}

@end
