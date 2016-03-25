//
//  Repo.h
//  ShipHub
//
//  Created by James Howard on 3/21/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MetadataItem.h"

@interface Repo : MetadataItem

@property (readonly) NSString *fullName;
@property (readonly) BOOL hidden;
@property (readonly) NSString *name;
@property (readonly, getter=isPrivate) BOOL private;

@property (readonly) NSString *repoDescription;

@end