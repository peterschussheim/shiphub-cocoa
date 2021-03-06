//
//  WSSyncConnection.m
//  ShipHub
//
//  Created by James Howard on 5/20/16.
//  Copyright © 2016 Real Artists, Inc. All rights reserved.
//

#import "WSSyncConnection.h"

#import "Auth.h"
#import "Error.h"
#import "Extras.h"
#import "IssueIdentifier.h"
#import "JSON.h"
#import "Reachability.h"

#import <SocketRocket/SRWebSocket.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

static NSString *const MessageFieldType = @"msg";

// Outgoing MessageTypes:
static NSString *const MessageHello = @"hello";
static NSString *const MessageViewing = @"viewing";

// Incoming MessageTypes:
static NSString *const MessageSync = @"sync";
static NSString *const MessagePurge = @"purge";
static NSString *const MessageBilling = @"subscription";
static NSString *const MessageRateLimit = @"ratelimit";

// Shared Message fields
static NSString *const MessageFieldVersions = @"versions";
static NSString *const MessageFieldSpiderProgress = @"spiderProgress";

// Hello Message fields
static NSString *const MessageFieldClient = @"client";

// Sync Message fields
static NSString *const MessageFieldLogs = @"logs";
static NSString *const MessageFieldRemaining = @"remaining";

// Viewing Message fields
static NSString *const MessageFieldViewingIssue = @"issue";

// Hello (Reply) Message fields
static NSString *const MessageFieldPurgeIdentifier = @"purgeIdentifier";
static NSString *const MessageFieldUpgrade = @"upgrade";
static NSString *const MessageFieldNewVersion = @"newVersion";
static NSString *const MessageFieldReleaseNotes = @"releaseNotes";
static NSString *const MessageFieldURL = @"url";
static NSString *const MessageFieldRequired = @"required";
static NSString *const MessageFieldHelloVersion = @"version";

// Billing Message fields
static NSString *const MessageFieldBillingMode = @"mode";
static NSString *const MessageFieldBillingTrialEndDate = @"trialEndDate";

// Rate Limit Message fields
static NSString *const MessageFieldRateLimitedUntil = @"until";

// Spider Progress fields
static NSString *const MessageFieldProgress = @"progress";

typedef NS_ENUM(uint8_t, MessageHeader) {
    MessageHeaderPlainText = 0,
    MessageHeaderDeflate = 1,
};

static uint64_t ServerHelloMinimumVersion = 2;

const double MaxConnectWaitTime = 3 * 60; // don't wait longer than this to establish a connection. retry if we can't get it in this time.
const double MaxReceiveWaitTime = 3 * 60; // don't wait longer than this to receive any data. retry if we don't get anything in this time.

@interface WSSyncConnection () <SRWebSocketDelegate> {
    dispatch_queue_t _q;
    dispatch_source_t _heartbeat;
    
    NSDictionary *_syncVersions;
    NSURL *_syncURL;
    
    BOOL _socketOpen;
    BOOL _asleep;
    
    double _connectTime; // the moment we tried to open the connection
    double _lastReceiveTime; // the last time we've received any data
}

@property SRWebSocket *socket;
@property NSInteger logEntryTotalRemaining;

@property NSString *lastViewedIssueIdentifier;

@end

@implementation WSSyncConnection

- (id)initWithAuth:(Auth *)auth {
    if (self = [super initWithAuth:auth]) {
        _syncURL = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"https://%@/api/sync", auth.account.shipHost]];
        _q = dispatch_queue_create("WSSyncConnection", NULL);
        
        dispatch_source_t heartbeat = _heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _q);
        __weak __typeof(self) weakSelf = self;
        dispatch_source_set_timer(_heartbeat, DISPATCH_TIME_NOW, 60.0 * NSEC_PER_SEC, 10.0 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_heartbeat, ^{
            id strongSelf = weakSelf;
            [strongSelf heartbeat:NO];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            dispatch_resume(heartbeat);
        });
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:ReachabilityDidChangeNotification object:[Reachability sharedInstance]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(authChanged:) name:AuthStateChangedNotification object:nil];
        
#if TARGET_OS_IPHONE
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
#else
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(beginSleep:) name:NSWorkspaceWillSleepNotification object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(endSleep:) name:NSWorkspaceDidWakeNotification object:nil];
#endif
    }
    return self;
}

- (void)dealloc {
    _socket.delegate = nil;
    [_socket close];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)authChanged:(NSNotification *)note {
    if (self.auth == note.object) {
        if (self.auth.authState == AuthStateValid) {
            dispatch_async(_q, ^{
                [self disconnect];
                [self connect];
            });
        } else {
            dispatch_async(_q, ^{
                [self disconnect];
            });
        }
    }
}

- (void)syncWithVersions:(NSDictionary *)versions {
    dispatch_async(_q, ^{
        _syncVersions = [versions copy];
        [self heartbeat:YES];
    });
}

- (void)connect {
    dispatch_assert_current_queue(_q);
    
    if (!_socket && _syncVersions != nil && self.auth.token) {
        DebugLog(@"Opening socket");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate syncConnectionWillConnect:self];
        });
        
        self.logEntryTotalRemaining = -1;
        _connectTime = [NSDate extras_monotonicTime];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_syncURL];
        [self.auth addAuthHeadersToRequest:request];
        request.timeoutInterval = MaxConnectWaitTime;
        _socket = [[SRWebSocket alloc] initWithURLRequest:request protocols:@[@"V1"]];
        _socket.delegate = self;
        [_socket setDelegateDispatchQueue:_q];
        [_socket open];
    }
}

- (void)disconnect {
    dispatch_assert_current_queue(_q);
    
    if (_socket) {
        DebugLog(@"Closing socket");
        self.logEntryTotalRemaining = -1;
        _socket.delegate = nil;
        [_socket close];
        _socket = nil;
        _socketOpen = NO;
        _connectTime = 0;
        _lastReceiveTime = 0;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate syncConnectionDidDisconnect:self];
        });
    }
}

- (void)reset {
    dispatch_assert_current_queue(_q);
    
    [self disconnect];
    _syncVersions = nil;
}

- (void)refresh {
    dispatch_async(_q, ^{
        if (_socket) {
            self.logEntryTotalRemaining = -1;
            _socket.delegate = nil;
            [_socket close];
            _socket = nil;
            _socketOpen = NO;
            _connectTime = 0;
            _lastReceiveTime = 0;
            // don't tell delegate that we closed
        }
        
        [self connect];
    });
}

- (void)sendMessage:(NSDictionary *)message {
    dispatch_assert_current_queue(_q);
    
    if (_socketOpen) {
        NSError *err = nil;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&err];
        NSMutableData *msgData = [[NSMutableData alloc] initWithLength:1 + bodyData.length];
        uint8_t *msgBytes = msgData.mutableBytes;
        msgBytes[0] = MessageHeaderPlainText;
        memcpy(msgBytes+1, bodyData.bytes, bodyData.length);
        if (err) {
            ErrLog(@"%@", err);
        }
        DebugLog(@"Sending %@", message);
        [_socket sendData:msgData error:NULL];
    }
}

- (NSString *)clientVersion {
    static dispatch_once_t onceToken;
    static NSString *clientVersion;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *appIdentifier = [bundle bundleIdentifier];
        NSString *appVersion = [bundle infoDictionary][@"CFBundleShortVersionString"];
        NSString *buildNumber = [bundle infoDictionary][@"CFBundleVersion"];
        NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
#if TARGET_OS_IPHONE
        NSString *platform = @"iOS";
#else
        NSString *platform = @"OS X";
#endif
        clientVersion = [NSString stringWithFormat:@"%@ %@ (%@), %@ %td.%td.%td", appIdentifier, appVersion, buildNumber, platform, osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion];
    });
    return clientVersion;
}


- (void)sendHello {
    Trace();
    
    dispatch_assert_current_queue(_q);
    
    NSDictionary *hello = @{ MessageFieldType : MessageHello,
                             MessageFieldClient : [self clientVersion],
                             MessageFieldVersions : _syncVersions };
    
    [self sendMessage:hello];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)rawMessage {
    _lastReceiveTime = [NSDate extras_monotonicTime];
    
    NSData *data = nil;
    if ([rawMessage isKindOfClass:[NSData class]]) {
        data = rawMessage;
    } else if ([rawMessage isKindOfClass:[NSString class]]) {
        data = [rawMessage dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        ErrLog(@"Received unexpected message: %@", rawMessage);
        return;
    }
    
    if ([data length] < 1) {
        ErrLog(@"Received short message: %@", data);
        return;
    }
    
    MessageHeader header = ((uint8_t *)[data bytes])[0];
    NSData *bodyData = [data subdataWithRange:NSMakeRange(1, data.length-1)];
    if (header == MessageHeaderDeflate) {
        bodyData = [bodyData inflate];
        if (!bodyData) {
            ErrLog(@"Unable to inflate message");
            return;
        }
    }
    
    NSError *err = nil;
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&err];
    if (err) {
        ErrLog(@"%@", err);
        return;
    }
    
#if DEBUG
    fprintf(stderr, "%s WSSyncConnection received message: %s\n", [[[NSDate date] description] UTF8String], [[msg description] UTF8String]);
#endif
    
    
    NSString *type = msg[MessageFieldType];
    
    if ([type isEqualToString:MessageHello]) {
        [self.delegate syncConnectionDidConnect:self];
        
        uint64_t serverVersion = [msg[MessageFieldHelloVersion] unsignedLongLongValue];
        if (serverVersion < ServerHelloMinimumVersion) {
            ErrLog(@"Server version is too low");
            [self.delegate syncConnectionRequiresUpdatedServer:self];
            [self disconnect];
            return;
        }
        
        NSString *purgeIdentifier = msg[MessageFieldPurgeIdentifier];
        NSDictionary *upgrade = msg[MessageFieldUpgrade];
        
        NSDictionary *spiderProgress = msg[MessageFieldSpiderProgress];
        id spiderProgressNumber = ([spiderProgress isKindOfClass:[NSDictionary class]] ? spiderProgress[MessageFieldProgress] : nil) ?: @(1.0);
        [self.delegate syncConnection:self updateSpiderProgress:[spiderProgressNumber doubleValue]];
        
        BOOL mustUpgrade = [upgrade[@"required"] boolValue];
        if (mustUpgrade) {
            [self.delegate syncConnectionRequiresSoftwareUpdate:self];
            [self disconnect];
            return;
        }
        
        if ([self.delegate syncConnection:self didReceivePurgeIdentifier:purgeIdentifier]) {
            [self reset];
            return;
        }
    } else if ([type isEqualToString:MessageSync]) {
        _syncVersions = msg[MessageFieldVersions];
        
        NSArray *entries = [msg[MessageFieldLogs] arrayByMappingObjects:^id(id obj) {
            return [SyncEntry entryWithDictionary:obj];
        }];
        
        NSInteger remaining = [msg[MessageFieldRemaining] integerValue];
        NSInteger totalRemaining = remaining + [entries count];
        if (_logEntryTotalRemaining < 0 || totalRemaining > _logEntriesRemaining) {
            _logEntryTotalRemaining = totalRemaining;
        }
        if (remaining == 0) {
            _logEntryTotalRemaining = totalRemaining = 0;
        }
        double progress = 1.0;
        if (_logEntryTotalRemaining > 0) {
            progress = (double)(_logEntryTotalRemaining - remaining) / (double)_logEntryTotalRemaining;
            progress = MIN(progress, 1.0);
            progress = MAX(progress, 0.0);
        }
        
        NSDictionary *spiderProgress = msg[MessageFieldSpiderProgress];
        id spiderProgressNumber = ([spiderProgress isKindOfClass:[NSDictionary class]] ? spiderProgress[MessageFieldProgress] : nil) ?: @(1.0);
        
        self.logEntriesRemaining = remaining;
                
        [self.delegate syncConnection:self receivedEntries:entries versions:_syncVersions logProgress:progress spiderProgress:[spiderProgressNumber doubleValue]];
    } else if ([type isEqualToString:MessageBilling]) {
        [self.delegate syncConnection:self didReceiveBillingUpdate:msg];
    } else if ([type isEqualToString:MessageRateLimit]) {
        [self.delegate syncConnection:self didReceiveRateLimit:[NSDate dateWithJSONString:msg[MessageFieldRateLimitedUntil]]];
    } else {
        DebugLog(@"Unknown message: %@", type);
    }
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    Trace();
    _socketOpen = YES;
    [self sendHello];
    
    if (_lastViewedIssueIdentifier) {
        NSDictionary *msg = @{ MessageFieldType : MessageViewing,
                               MessageFieldViewingIssue : _lastViewedIssueIdentifier };
        _lastViewedIssueIdentifier = nil;
        [self sendMessage:msg];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    ErrLog(@"%@", error);
    [self disconnect];
    
    NSNumber *httpError = error.userInfo[SRHTTPResponseErrorKey];
    if (httpError && [httpError integerValue] == 401) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.auth invalidate];
        });
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    DebugLog(@"webSocketDidCloseWithCode:%td reason:%@ clean:%d", code, reason, wasClean);
    _socketOpen = NO;
    [self disconnect];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload {
    Trace();
    _lastReceiveTime = [NSDate extras_monotonicTime];
}

- (void)heartbeat:(BOOL)force {
    Reachability *r = [Reachability sharedInstance];
    if (!_asleep && !_socket && (force || !r.receivedFirstUpdate || r.reachable)) {
        [self connect];
    } else if (_socket) {
        // ok, we've got a socket. now to find out if it's still alive
        double now = [NSDate extras_monotonicTime];
        if (!_socketOpen) {
            if (now - _connectTime > MaxConnectWaitTime) {
                ErrLog(@"Waited %.0fs for socket to open and it hasn't. Retrying ...", (now - _connectTime));
                [self disconnect];
                [self connect];
            }
        } else if (now - _lastReceiveTime > MaxReceiveWaitTime) {
            ErrLog(@"Waited %.0fs for socket to send data or respond to a ping and it hasn't. Retrying ...", (now - _lastReceiveTime));
            [self disconnect];
            [self connect];
        } else /* socket is open and we've gotten data somewhat recently */ {
            [_socket sendPing:nil error:NULL];
        }
    }
}

- (void)reachabilityChanged:(NSNotification *)note {
    DebugLog(@"%@", note.userInfo);
    dispatch_async(_q, ^{
        BOOL reachable = [note.userInfo[ReachabilityKey] boolValue];
        if (reachable && !_socket) {
            [self connect];
        } else if (!reachable && _socket) {
            [self disconnect];
        }
    });
}

- (void)enterForeground:(NSNotification *)note {
    Trace();
    dispatch_async(_q, ^{
        if (!_socket) {
            [self connect];
        }
    });
}

-  (void)beginSleep:(NSNotification *)note {
    Trace();
    dispatch_async(_q, ^{
        _asleep = YES;
        [self disconnect];
    });
}

- (void)endSleep:(NSNotification *)note {
    Trace();
    dispatch_async(_q, ^{
        _asleep = NO;
        BOOL reachable = [[Reachability sharedInstance] isReachable];
        DebugLog(@"reachable: %d _socket: %p", reachable, _socket);
        if (reachable && !_socket) {
            [self connect];
        }
    });
}

- (void)updateIssue:(id)issueIdentifier {
    NSDictionary *msg = @{ MessageFieldType : MessageViewing,
                           MessageFieldViewingIssue : issueIdentifier };
    dispatch_async(_q, ^{
        if (_socket) {
            [self sendMessage:msg];
        } else {
            _lastViewedIssueIdentifier = issueIdentifier;
        }
    });
}

@end
