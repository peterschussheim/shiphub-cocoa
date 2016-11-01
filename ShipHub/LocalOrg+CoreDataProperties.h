//
//  LocalOrg+CoreDataProperties.h
//  ShipHub
//
//  Created by James Howard on 3/14/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "LocalOrg.h"

NS_ASSUME_NONNULL_BEGIN

@interface LocalOrg (CoreDataProperties)

@property (nullable, nonatomic, retain) NSNumber *shipNeedsWebhookHelp;
@property (nullable, nonatomic, retain) NSSet<LocalUser *> *users;
@property (nullable, nonatomic, retain) NSSet<LocalProject *> *projects;

@end

@interface LocalOrg (CoreDataGeneratedAccessors)

- (void)addUsersObject:(LocalUser *)value;
- (void)removeUsersObject:(LocalUser *)value;
- (void)addUsers:(NSSet<LocalUser *> *)values;
- (void)removeUsers:(NSSet<LocalUser *> *)values;

- (void)addProjectsObject:(LocalProject *)value;
- (void)removeProjectsObject:(LocalProject *)value;
- (void)addProjects:(NSSet<LocalProject *> *)values;
- (void)removeProjects:(NSSet<LocalProject *> *)values;

@end

NS_ASSUME_NONNULL_END
