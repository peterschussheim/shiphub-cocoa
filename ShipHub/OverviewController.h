//
//  OverviewController.h
//  Ship
//
//  Created by James Howard on 6/3/15.
//  Copyright (c) 2015 Real Artists, Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#if !INCOMPLETE
@class CustomQuery;
@protocol ProblemSnapshot;
#endif

@interface OverviewController : NSWindowController

- (IBAction)searchAllProblems:(id)sender;

+ (OverviewController *)defaultOverviewController; // Returns either the first open overview controller or opens a new one if there are none.

#if !INCOMPLETE
- (IBAction)showDownloads:(id)sender;
- (void)openQuery:(CustomQuery *)query;

- (NSArray <id<ProblemSnapshot>> *)selectedProblemSnapshots;
#endif

@end