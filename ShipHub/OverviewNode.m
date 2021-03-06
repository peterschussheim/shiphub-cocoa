//
//  OverviewNode.m
//  Ship
//
//  Created by James Howard on 6/3/15.
//  Copyright (c) 2015 Real Artists, Inc. All rights reserved.
//

#import "OverviewNode.h"
#import "Extras.h"
#import "Defaults.h"

@implementation OverviewNode

- (id)init {
    if (self = [super init]) {
        _count = NSNotFound;
        _progress = -1.0;
        _allowChart = YES;
        _filterBarDefaultsToOpenState = YES;
        _cellIdentifier = @"BasicCell";
    }
    return self;
}

- (void)insertChild:(OverviewNode *)node atIndex:(NSUInteger)idx {
    if (!_children) {
        _children = [NSMutableArray array];
    }
    [_children insertObject:node atIndex:idx];
    node.parent = self;
}

- (void)addChild:(OverviewNode *)node {
    if (!_children) {
        _children = [NSMutableArray array];
    }
    [_children addObject:node];
    node.parent = self;
}

- (void)removeLastChild {
    OverviewNode *node = [_children lastObject];
    node.parent = nil;
    [_children removeLastObject];
}

- (void)removeChild:(OverviewNode *)node {
    node.parent = nil;
    [_children removeObject:node];
}

- (NSString *)childOrderKey {
    return [NSString stringWithFormat:@"OverviewNode.%@.ChildOrder", self.identifier];
}

static NSArray *mergeArrays(NSArray *a, NSArray *b, NSComparator cmp) {
    NSMutableArray *ret = [NSMutableArray new];
    NSUInteger ai = 0, bi = 0;
    NSUInteger ac = a.count, bc = b.count;
    while (ai < ac && bi < bc) {
        id ao = a[ai];
        id bo = b[bi];
        NSComparisonResult r = cmp(ao, bo);
        if (r == NSOrderedAscending) {
            [ret addObject:ao];
            ai++;
        } else {
            [ret addObject:bo];
            bi++;
        }
    }
    if (ai < ac) {
        [ret addObjectsFromArray:[a subarrayWithRange:NSMakeRange(ai, ac-ai)]];
    }
    if (bi < bc) {
        [ret addObjectsFromArray:[b subarrayWithRange:NSMakeRange(bi, bc-bi)]];
    }
    return ret;
}

+ (void)sortNodes:(NSMutableArray *)nodes withOrderKey:(NSString *)orderKey
{
    NSArray *savedOrder = [[NSUserDefaults standardUserDefaults] arrayForKey:orderKey];
    NSMutableDictionary *idToPos = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < savedOrder.count; i++) {
        idToPos[savedOrder[i]] = @(i);
    }
    
    // partition nodes into has savedOrder and not has savedOrder.
    // then sort the savedOrder ones by idToPos, and the not has savedOrder ones by defaultOrderKey, title
    // finally, merge them by defaultOrderKey, title
    
    NSMutableArray *withSavedOrder = [NSMutableArray arrayWithCapacity:savedOrder.count];
    NSMutableArray *withoutSavedOrder = [NSMutableArray new];
    
    for (OverviewNode *n in nodes) {
        if (idToPos[n.identifier]) {
            [withSavedOrder addObject:n];
        } else {
            [withoutSavedOrder addObject:n];
        }
    }
    
    [withSavedOrder sortUsingComparator:^NSComparisonResult(OverviewNode *n1, OverviewNode *n2) {
        NSNumber *p1 = idToPos[n1.identifier];
        NSNumber *p2 = idToPos[n2.identifier];
        NSAssert(p1 && p2, nil);
        return [p1 compare:p2];
    }];
    
    NSComparator nodeComparator = ^NSComparisonResult(OverviewNode *n1, OverviewNode *n2) {
        if (n1.defaultOrderKey < n2.defaultOrderKey) {
            return NSOrderedAscending;
        } else if (n1.defaultOrderKey > n2.defaultOrderKey) {
            return NSOrderedDescending;
        } else {
            return [n1.title localizedStandardCompare:n2.title];
        }
    };
    
    [withoutSavedOrder sortUsingComparator:nodeComparator];
    
    NSArray *merged = mergeArrays(withSavedOrder, withoutSavedOrder, nodeComparator);
    
    NSAssert(merged.count == nodes.count, nil);
    
    [nodes replaceObjectsInRange:NSMakeRange(0, merged.count) withObjectsFromArray:merged];
    
    [nodes makeObjectsPerformSelector:@selector(sortChildrenWithDefaults)];
}

- (void)sortChildrenWithDefaults {
    [[self class] sortNodes:_children withOrderKey:[self childOrderKey]];
}

+ (NSString *)rootNodeOrderKey {
    return @"OverviewNode.Root.ChildOrder";
}

+ (void)sortRootNodesWithDefaults:(NSMutableArray *)rootNodes {
    [self sortNodes:rootNodes withOrderKey:[self rootNodeOrderKey]];
}

+ (void)saveRootNodeOrder:(NSArray *)rootNodes {
    NSArray *savedOrder = [rootNodes arrayByMappingObjects:^id(id obj) {
        return [obj identifier];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:savedOrder forKey:[self rootNodeOrderKey]];
}

- (BOOL)moveChildWithIdentifier:(NSString *)identifier toIndex:(NSInteger)idx {
    NSUInteger pos = [_children indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger j, BOOL * _Nonnull stop) {
        return [identifier isEqualToString:[obj identifier]];
    }];
    
    if (pos == NSNotFound) return NO;
    [_children moveItemsAtIndexes:[NSIndexSet indexSetWithIndex:pos] toIndex:idx];
    NSArray *savedOrder = [_children arrayByMappingObjects:^id(id obj) {
        return [obj identifier];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:savedOrder forKey:[self childOrderKey]];
    return YES;
}

- (void)addKnob:(OverviewKnob *)knob {
    if (!_knobs) {
        _knobs = [NSMutableArray array];
    }
    [_knobs addObject:knob];
    knob.target = self;
    knob.action = @selector(knobUpdated:);
}

- (NSPredicate *)predicate {
    if (_predicate) return _predicate;
    if (_predicateBuilder) {
        return _predicateBuilder();
    }
    return nil;
}

- (NSString *)identifier {
    if (!_identifier) {
        NSMutableString *identifier = [NSMutableString stringWithString:self.title ?: @""];
        OverviewNode *parent = self.parent;
        if (parent) {
            [identifier insertString:@"." atIndex:0];
            [identifier insertString:[parent identifier] atIndex:0];
        }
        return identifier;
    }
    return _identifier;
}

- (void)knobUpdated:(id)sender {
    [self sendAction:self.action toTarget:self.target];
}

- (NSString *)path {
    if (!_path) {
        return self.title;
    }
    return _path;
}

@synthesize title = _title;

- (void)setTitle:(NSString *)title {
    NSParameterAssert(title);
    _title = title;
}

- (NSString *)title {
    return _title;
}

@end

@implementation OverviewKnob

- (id)initWithDefaultsIdentifier:(NSString *)identifier {
    if (self = [super init]) {
        _defaultsIdentifier = [identifier copy];
    }
    return self;
}

+ (instancetype)knobWithDefaultsIdentifier:(NSString *)identifier {
    return [[[self class] alloc] initWithDefaultsIdentifier:identifier];
}

- (void)reset { }

- (IBAction)moveBackward:(id)sender { }
- (IBAction)moveForward:(id)sender { }

@end

@interface DateKnob ()

@property (strong) IBOutlet NSSlider *slider;
@property (strong) IBOutlet NSBox *box;

@end

@implementation DateKnob

- (NSString *)nibName { return @"DateKnob"; }

- (id)initWithDefaultsIdentifier:(NSString *)identifier {
    if (self = [super initWithDefaultsIdentifier:identifier]) {
        _daysAgo = 7;
        if (self.defaultsIdentifier) {
            _daysAgo = [[NSUserDefaults standardUserDefaults] integerForKey:[self daysAgoDefaultsKey] fallback:_daysAgo];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _slider.integerValue = daysToValue(_daysAgo);
    [self update];
}

- (NSString *)daysAgoDefaultsKey {
    return [NSString stringWithFormat:@"%@.daysAgo", self.defaultsIdentifier];
}

static NSInteger valueToDays(NSInteger value) {
    switch (value) {
        case 4: return 1;
        case 3: return 7;
        case 2: return 30;
        case 1: return 90;
        case 0: return 365;
        default: return 1;
    }
}

static NSInteger daysToValue(NSInteger days) {
    switch (days) {
        case 1: return 4;
        case 7: return 3;
        case 30: return 2;
        case 90: return 1;
        case 365: return 0;
        default: return 4;
    }
}

static NSString *valueToString(NSInteger value) {
    switch (value) {
        case 3: return NSLocalizedString(@"Within the last week", nil);
        case 2: return NSLocalizedString(@"Within the last month", nil);
        case 1: return NSLocalizedString(@"Within the last 3 months", nil);
        case 0: return NSLocalizedString(@"Within the last year", nil);
        case 4:
        default: return NSLocalizedString(@"Within the last day", nil);
    }
}

- (void)update {
    _box.title = valueToString(daysToValue(_daysAgo));
}

- (IBAction)sliderChanged:(id)sender {
    _daysAgo = valueToDays(_slider.integerValue);
    [[NSUserDefaults standardUserDefaults] setInteger:_daysAgo forKey:[self daysAgoDefaultsKey]];
    [self update];
    [self sendAction:self.action toTarget:self.target];
}

- (IBAction)moveBackward:(id)sender {
    if (_slider.integerValue > _slider.minValue) {
        _slider.integerValue--;
        [self sliderChanged:sender];
    }
}

- (IBAction)moveForward:(id)sender {
    if (_slider.integerValue < _slider.maxValue) {
        _slider.integerValue++;
        [self sliderChanged:sender];
    }
}

@end
