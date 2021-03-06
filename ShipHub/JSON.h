//
//  JSON.h
//  ShipHub
//
//  Created by James Howard on 3/28/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class JSValue;

typedef NSString* (^JSONNameTransformer)(NSString *original);

@interface JSON : NSObject

+ (id)stringifyObject:(id)src;

+ (id)stringifyObject:(id)src withNameTransformer:(JSONNameTransformer)nameTransformer;

// Convert src into an ObjC object comprised of only JSON types (array, dictionary, string, null, number)
+ (id)serializeObject:(id)src withNameTransformer:(JSONNameTransformer)nameTransformer;

// Recursively serialize all object properties into an object passable to JSC
+ (id)JSRepresentableValueFromSerializedObject:(id)src;
+ (id)JSRepresentableValueFromSerializedObject:(id)src withNameTransformer:(JSONNameTransformer)nameTransformer;

+ (id)parseObject:(id)json withNameTransformer:(JSONNameTransformer)nameTransformer;

+ (JSONNameTransformer)passthroughNameTransformer;
+ (JSONNameTransformer)underbarsNameTransformer; // turns camelCase to camel_case
+ (JSONNameTransformer)underbarsAndIDNameTransformer;

+ (JSONNameTransformer)githubToCocoaNameTransformer; // turns bar_case to barCase and renames a few field names (id => identifier, comments => commentsCount, events => eventsCount)

@end

@interface NSObject (JSONStringify)

- (id)JSONDescription;

@end
