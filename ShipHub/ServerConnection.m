//
//  ServerConnection.m
//  ShipHub
//
//  Created by James Howard on 2/26/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//

#import "ServerConnection.h"

#import "Auth.h"
#import "Error.h"
#import "Extras.h"

#import "PATController.h"

@interface ServerConnection ()

@property (strong) Auth *auth;
@property (strong) PATController *pat;

@end

@implementation ServerConnection

- (id)initWithAuth:(Auth *)auth {
    if (self = [super init]) {
        self.auth = auth;
        self.pat = [[PATController alloc] initWithAuth:auth];
    }
    return self;
}

- (NSMutableURLRequest *)requestWithHost:(NSString *)host endpoint:(NSString *)endpoint authenticated:(BOOL)authenticate headers:(NSDictionary *)headers
{
    NSURLComponents *comps = [NSURLComponents new];
    comps.scheme = @"https";
    comps.host = host;
    comps.path = endpoint;
    
    NSURL *URL = [comps URL];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:URL];
    if (authenticate) {
        [_auth addAuthHeadersToRequest:req];
    }
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    for (NSString *key in [headers allKeys]) {
        [req setValue:headers[key] forHTTPHeaderField:key];
    }
    
    return req;
}

- (void)perform:(NSString *)method on:(NSString *)endpoint body:(id)jsonBody completion:(void (^)(id jsonResponse, NSError *error))completion {
    [self perform:method on:endpoint headers:nil body:jsonBody completion:completion];
}

- (void)perform:(NSString *)method on:(NSString *)endpoint headers:(NSDictionary *)headers body:(id)jsonBody completion:(void (^)(id jsonResponse, NSError *error))completion
{
    [self perform:method on:endpoint forGitHub:YES headers:headers body:jsonBody completion:completion];
}

#define DebugResponse(data, response, error) do { DebugLog(@"response:\n%@\ndata:\n%@\nerror:%@", [response debugDescription], [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], error); } while (0)

- (void)perform:(NSString *)method on:(NSString *)endpoint forGitHub:(BOOL)forGitHub headers:(NSDictionary *)headers body:(id)jsonBody completion:(void (^)(id jsonResponse, NSError *error))completion
{
    [self perform:method on:endpoint forGitHub:forGitHub headers:headers body:jsonBody extendedCompletion:^(NSHTTPURLResponse *httpResponse, id jsonResponse, NSError *error) {
        completion(jsonResponse, error);
    }];
}

- (void)perform:(NSString *)method on:(NSString *)endpoint forGitHub:(BOOL)forGitHub headers:(NSDictionary *)headers body:(id)jsonBody extendedCompletion:(void (^)(NSHTTPURLResponse *httpResponse, id jsonResponse, NSError *error))completion
{
    if (forGitHub && ![_auth.account.shipHost isEqualToString:_auth.account.ghHost]) {
        endpoint = [@"/github" stringByAppendingString:endpoint];
    }
    
    NSMutableURLRequest *request = [self requestWithHost:_auth.account.shipHost endpoint:endpoint authenticated:YES headers:headers];
    request.HTTPMethod = method;
    if (!([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"])) {
        request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    }
    
    if (jsonBody) {
        NSError *err = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:jsonBody options:0 error:&err];
        
        if (err) {
            completion(nil, nil, err);
            return;
        }
    }
    
    [self _runRequest:request extendedCompletion:completion];
}

BOOL IsPatRequest(NSURLRequest *request) {
    return request.allHTTPHeaderFields[@"X-Authorization-PAT"] != nil;
}

- (NSError *)_parseError:(NSData *)data response:(NSHTTPURLResponse *)http {
    NSError *error = nil;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[ShipErrorUserInfoHTTPResponseCodeKey] = @(http.statusCode);
    
    id errorJSON = nil;
    if ([data length]) {
        errorJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([errorJSON isKindOfClass:[NSDictionary class]]) {
            NSArray *errors = [errorJSON objectForKey:@"errors"];
            NSString *message = [errorJSON objectForKey:@"message"];
            NSString *desc = nil;
            if ([errors isKindOfClass:[NSArray class]] && [errors count] > 0) {
                id err1 = [errors firstObject];
                if ([err1 isKindOfClass:[NSDictionary class]]) {
                    id errmsg = [err1 objectForKey:@"message"];
                    if ([errmsg isKindOfClass:[NSString class]] && [errmsg length] > 0) {
                        desc = errmsg;
                    } else if ([errmsg isKindOfClass:[NSArray class]] && [errmsg count] > 0) {
                        errmsg = [errmsg firstObject];
                        if ([errmsg isKindOfClass:[NSString class]] && [errmsg length] > 0) {
                            desc = errmsg;
                        }
                    }
                } else if ([err1 isKindOfClass:[NSString class]] && [err1 length] > 0) {
                    desc = err1;
                }
            }
            if (desc == nil && [message isKindOfClass:[NSString class]] && [message length] > 0) {
                desc = message;
            }
            if ([desc length]) {
                userInfo[NSLocalizedDescriptionKey] = desc;
            }
        }
    }
    
    if (errorJSON) {
        userInfo[ShipErrorUserInfoErrorJSONBodyKey] = errorJSON;
    }
    
    error = [NSError shipErrorWithCode:ShipErrorCodeUnexpectedServerResponse userInfo:userInfo];
    
    return error;
}

- (void)_runRequest:(NSURLRequest *)request extendedCompletion:(void (^)(NSHTTPURLResponse *httpResponse, id jsonResponse, NSError *error))completion {
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSHTTPURLResponse *http = (id)response;
        BOOL viaPAT = IsPatRequest(request);
        BOOL authValid = [_auth checkResponse:http requestWasViaPersonalAccessToken:viaPAT];
        if (authValid || viaPAT) {
            
            if (http.statusCode < 200 || http.statusCode >= 400) {
                if (!error) {
                    
                    error = [self _parseError:data response:http];
                    
                    if (!viaPAT || !authValid) {
                        void (^patCompletion)(NSURLRequest *, BOOL) = ^(NSURLRequest *replayRequest, BOOL didPrompt) {
                            if (replayRequest) {
                                [self _runRequest:replayRequest extendedCompletion:completion];
                            } else if (didPrompt) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    completion(nil, nil, [NSError cancelError]);
                                });
                            } else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    completion(nil, nil, error);
                                });
                            }
                        };
                        
                        if ([_pat handleResponse:http forInitialRequest:request completion:patCompletion]) {
                            return;
                        }
                    }
                }
            }
            
            if (!error) {
                id responseJSON = nil;
                if (data.length) {
                    NSError *err = nil;
                    responseJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
                    if (err) {
                        error = [NSError shipErrorWithCode:ShipErrorCodeUnexpectedServerResponse];
                    }
                }
                
                if (error) {
                    DebugResponse(data, response, error);
                }
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    completion(http, responseJSON, error);
                });
            } else {
                DebugResponse(data, response, error);
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    completion(http, nil, error);
                });
            }
            
        } else {
            error = [NSError shipErrorWithCode:ShipErrorCodeNeedsAuthToken];
            
            DebugResponse(data, response, error);
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(http, nil, error);
            });
        }
        
    }] resume];
}

@end
