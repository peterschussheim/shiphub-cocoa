//
//  MetadataStoreInternal.h
//  ShipHub
//
//  Created by James Howard on 3/21/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//

#import "MetadataStore.h"

#import "Billing.h"

@class LocalAccount;

@interface MetadataStore (Internal)

+ (BOOL)changeNotificationContainsMetadata:(NSNotification *)mocNote;

// Read data out of ctx and store in immutable data objects accessible from any thread.
// Must be called on ctx's private queue.
- (instancetype)initWithMOC:(NSManagedObjectContext *)ctx billingState:(BillingState)state currentUserIdentifier:(NSNumber *)currentUserIdentifier;

- (Account *)accountWithLocalAccount:(LocalAccount *)la;

@end
