//
//  APIProxy.h
//  ShipHub
//
//  Created by James Howard on 4/20/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Issue;

typedef void (^APIProxyCompletion)(NSString *jsonResult, NSError *err);

typedef void (^APIProxyUpdatedIssue)(Issue *issue);

typedef void (^APIProxyRefreshTimeline)(void);

@interface APIProxy : NSObject

+ (instancetype)proxyWithRequest:(NSDictionary *)request completion:(APIProxyCompletion)completion;

@property (copy) APIProxyUpdatedIssue updatedIssueHandler;
@property (copy) APIProxyRefreshTimeline refreshTimelineHandler;

- (void)resume;

@end
