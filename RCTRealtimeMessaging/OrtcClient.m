//
//  OrtcClient.m
//  OrtcClient
//
//  Created by Rafael Cabral on 2/2/12.
//  Copyright (c) 2012 IBT. All rights reserved.
//

#import "OrtcClient.h"
#import "Balancer.h"

// Class Extension (private methods)
@interface OrtcClient()
{
@private
    RCTSRWebSocket* _webSocket;
    
    id<OrtcClientDelegate> _ortcDelegate;
    
    NSMutableDictionary* _subscribedChannels;
    NSMutableDictionary* _permissions;
    NSMutableDictionary* messagesBuffer;
    NSMutableDictionary* opCases;
    NSMutableDictionary* errCases;
    
    NSString* applicationKey;
    NSString* authenticationToken;
    
    BOOL isCluster;
    BOOL isConnecting;
    BOOL isReconnecting;
    BOOL hasConnectedFirstTime;
    BOOL stopReconnecting;
    BOOL doFallback;
    
    NSDate* sessionCreatedAt;
    int sessionExpirationTime;
    
    // Time in seconds
    int heartbeatTime;// = heartbeatDefaultTime; // Heartbeat interval time
    int heartbeatFails;// = heartbeatDefaultFails; // Heartbeat max fails
    NSTimer *heartbeatTimer;
    BOOL heartbeatActive;
}
- (id)initWithConfig:(id<OrtcClientDelegate>) aDelegate;

- (void)opValidated:(NSString*) message;
- (void)opSubscribed:(NSString*) message;
- (void)opUnsubscribed:(NSString*) message;
- (void)opException:(NSString*) message;
- (void)opReceive:(NSString*) message;

- (void)parseReceivedMessage:(NSString*) aMessage;
- (void)doConnect:(id) sender;
- (void)processConnect:(id) sender;
- (BOOL)isEmpty:(id) thing;
- (NSError*)generateError:(NSString*) errText;
- (NSString*)randomString:(u_int32_t) size;
- (NSString*)getClusterServer:(BOOL) isPostingAuth aPostUrl:(NSString*) postUrl;
- (u_int32_t)randomInRangeLo:(u_int32_t) loBound toHi:(u_int32_t) hiBound;
- (NSString*)generateId:(int) size;
- (BOOL)ortcIsValidInput:(NSString*) input;
- (BOOL)ortcIsValidUrl:(NSString*) input;
- (NSString*)readLocalStorage:(NSString*) sessionStorageName;
- (void)createLocalStorage:(NSString*) sessionStorageName;
+ (void) setDEVICE_TOKEN:(NSString *) deviceToken;
+ (NSString *) getDEVICE_TOKEN;

- (void)delegateConnectedCallback:(OrtcClient*) ortc;
- (void)delegateDisconnectedCallback:(OrtcClient*) ortc;
- (void)delegateSubscribedCallback:(OrtcClient*) ortc channel:(NSString*) channel;
- (void)delegateUnsubscribedCallback:(OrtcClient*) ortc channel:(NSString*) channel;
- (void)delegateExceptionCallback:(OrtcClient*) ortc error:(NSError*) aError;
- (void)delegateReconnectingCallback:(OrtcClient*) ortc;
- (void)delegateReconnectedCallback:(OrtcClient*) ortc;

@end

@interface ChannelSubscription : NSObject
{
}

@property (assign) BOOL isSubscribing;
@property (assign) BOOL isSubscribed;
@property (assign) BOOL subscribeOnReconnected;
@property (assign) BOOL withNotifications;
@property (nonatomic, strong) void (^onMessage)(OrtcClient* ortc, NSString* channel, NSString* message);

@end

@interface PresenceRequest : NSObject {
 	NSMutableData *receivedData;
 	bool isResponseJSON;
}
@property (nonatomic,retain) NSMutableData *receivedData;
@property bool isResponseJSON;
@property (nonatomic, strong) void (^callback)(NSError* error, NSString* result);
@property (nonatomic, strong) void (^callbackDictionary)(NSError* error, NSDictionary* result);

- (void)get: (NSMutableURLRequest *)request;
- (void)post: (NSMutableURLRequest *)request;

@end


@implementation OrtcClient

#pragma mark Attributes

@synthesize id;
@synthesize url;
@synthesize clusterUrl;
@synthesize connectionTimeout;
@synthesize isConnected;
@synthesize connectionMetadata;
@synthesize announcementSubChannel;
@synthesize sessionId;

#pragma mark Enumerators

typedef enum {
    opValidate,
    opSubscribe,
    opUnsubscribe,
    opException
} opCodes;

typedef enum {
    errValidate,
    errSubscribe,
    errSubscribeMaxSize,
    errUnsubscribeMaxSize,
    errSendMaxSize
} errCodes;

#pragma mark Regex patterns

//NSString* const TESTER= @"^a\\[\"\\{\\\\\"op\\\\\"(.*?[^\"]+)\\\\\",(.*?)\\}\"\\]$";
//NSString* const OPERATION_PATTERN = @"^a\\[\"\\{\\\"op\\\":\\\"(.*?[^\"]+)\\\",(.*?)\\}\"\\]$";
NSString* const OPERATION_PATTERN = @"^a\\[\"\\{\\\\\"op\\\\\":\\\\\"(.*?[^\"]+)\\\\\",(.*?)\\}\"\\]$";

NSString* const VALIDATED_PATTERN = @"^(\\\\\"up\\\\\":){1}(.*?)(,\\\\\"set\\\\\":(.*?))?$";
NSString* const CHANNEL_PATTERN = @"^\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\"$";
NSString* const EXCEPTION_PATTERN = @"^\\\\\"ex\\\\\":\\{(\\\\\"op\\\\\":\\\\\"(.*?[^\"]+)\\\\\",)?(\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\",)?\\\\\"ex\\\\\":\\\\\"(.*?)\\\\\"\\}$";
NSString* const RECEIVED_PATTERN = @"^a\\[\"\\{\\\\\"ch\\\\\":\\\\\"(.*?)\\\\\",\\\\\"m\\\\\":\\\\\"([\\s\\S]*?)\\\\\"\\}\"\\]$";
NSString* const MULTI_PART_MESSAGE_PATTERN = @"^(.[^_]*?)_(.[^-]*?)-(.[^_]*?)_([\\s\\S]*?)$";
NSString* const CLUSTER_RESPONSE_PATTERN = @"^var SOCKET_SERVER = \\\"(.*?)\\\";$";
NSString* const DEVICE_TOKEN_PATTERN = @"[0-9A-Fa-f]{64}";

#pragma mark Maximum sizes

int const MAX_MESSAGE_SIZE = 600;
int const MAX_CHANNEL_SIZE = 100;
int const MAX_CONNECTION_METADATA_SIZE = 256;
NSString* SESSION_STORAGE_NAME = @"ortcsession-";

#pragma mark Notifications constants

NSString* const PLATFORM = @"Apns";
#define WITH_NOTIFICATIONS YES
#define WITHOUT_NOTIFICATIONS NO

#pragma mark Redefined properties

- (void) setUrl:(NSString*) aUrl
{
    isCluster = NO;
    url = [aUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void) setClusterUrl:(NSString*) aClusterUrl
{
    isCluster = YES;
    clusterUrl = [aClusterUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark Public methods

- (void)connect:(NSString*) aApplicationKey authenticationToken:(NSString*) aAuthenticationToken
{
    /*
     * Sanity Checks.
     */
    if (isConnected) {
        [self delegateExceptionCallback:self error:[self generateError:@"Already connected"]];
    }
    else if (!url && !clusterUrl) {
        [self delegateExceptionCallback:self error:[self generateError:@"URL and Cluster URL are null or empty"]];
    }
    else if (!aApplicationKey) {
        [self delegateExceptionCallback:self error:[self generateError:@"Application Key is null or empty"]];
    }
    else if (!aAuthenticationToken) {
        [self delegateExceptionCallback:self error:[self generateError:@"Authentication Token is null or empty"]];
    }
    else if (!isCluster && ![self ortcIsValidUrl:url]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Invalid URL"]];
    }
    else if (isCluster && ![self ortcIsValidUrl:clusterUrl]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Invalid Cluster URL"]];
    }
    else if (![self ortcIsValidInput:aApplicationKey]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Application Key has invalid characters"]];
    }
    else if (![self ortcIsValidInput:aAuthenticationToken]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Authentication Token has invalid characters"]];
    }
    else if (announcementSubChannel && ![self ortcIsValidInput:announcementSubChannel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Announcement Subchannel has invalid characters"]];
    }
    else if (![self isEmpty:connectionMetadata] && [connectionMetadata length] > MAX_CONNECTION_METADATA_SIZE) {
        [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Connection metadata size exceeds the limit of %d characters", MAX_CONNECTION_METADATA_SIZE]]];
    }
    else if (isConnecting) {
        [self delegateExceptionCallback:self error:[self generateError:@"Already trying to connect"]];
    }
    else {
        applicationKey = aApplicationKey;
        authenticationToken = aAuthenticationToken;
        
        isConnecting = YES;
        isReconnecting = NO;
        stopReconnecting = NO;
        
        [self doConnect:self];
    }
}

- (void)send:(NSString*) channel message:(NSString*) aMessage
{
    /*
     * Sanity Checks.
     */
    if (!isConnected) {
        [self delegateExceptionCallback:self error:[self generateError:@"Not connected"]];
    }
    else if ([self isEmpty:channel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Channel is null or empty"]];
    }
    else if (![self ortcIsValidInput:channel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Channel has invalid characters"]];
    }
    else if ([self isEmpty:aMessage]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Message is null or empty"]];
    }
    else {
        
        aMessage = [[aMessage stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
		aMessage = [aMessage stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
		
		NSData* channelBytes = [channel dataUsingEncoding:NSUTF8StringEncoding];
        
        if (channelBytes.length >= MAX_CHANNEL_SIZE) {
            [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Channel size exceeds the limit of %d characters", MAX_CHANNEL_SIZE]]];
        }
        else {
            unsigned long domainChannelIndex = (int)[channel rangeOfString:@":"].location;
            NSString* channelToValidate = channel;
            NSString* hashPerm = nil;
            

            if (domainChannelIndex != NSNotFound) {
                channelToValidate = [[channel substringToIndex:domainChannelIndex + 1] stringByAppendingString:@"*"];
            }
            
            if (_permissions) {
                hashPerm = [_permissions objectForKey:channelToValidate] ? [_permissions objectForKey:channelToValidate] : [_permissions objectForKey:channel];
            }
            
            if (_permissions && !hashPerm) {
                [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"No permission found to send to the channel '%@'", channel]]];
            }
            else {
				
                NSData* messageBytes = [NSData dataWithBytes:[aMessage UTF8String] length:[aMessage lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
                
                NSMutableArray* messageParts = [[NSMutableArray alloc] init];
                unsigned long pos = 0;
                unsigned long remaining;
                NSString* messageId = [self generateId:8];
                
                // Multi part
                while ((remaining = messageBytes.length - pos) > 0) {
                    unsigned long arraySize = 0;
                    
                    if (remaining >= MAX_MESSAGE_SIZE - channelBytes.length) {
                        arraySize = MAX_MESSAGE_SIZE - ((int)channelBytes.length);
                    }
                    else {
                        arraySize = remaining;
                    }
                    
                    Byte messagePart[arraySize];
                    
                    [messageBytes getBytes:messagePart range:NSMakeRange(pos, arraySize)];
                    
                    [messageParts addObject:[[NSString alloc] initWithBytes:messagePart length:arraySize encoding:NSUTF8StringEncoding]];
                    
                    pos += arraySize;
                }
                
                int counter = 1;
                
                for (NSString* __strong messageToSend in messageParts) {
                    NSString* encodedData = [[NSString alloc] initWithData:[NSData dataWithBytes:[messageToSend UTF8String] length:[messageToSend lengthOfBytesUsingEncoding:NSUTF8StringEncoding]] encoding:NSUTF8StringEncoding];
                    
                    NSString* aString = [NSString stringWithFormat:@"\"send;%@;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm, [[[[[[messageId stringByAppendingString:@"_"] stringByAppendingString:[NSString stringWithFormat:@"%d", counter]] stringByAppendingString:@"-"] stringByAppendingString:[NSString stringWithFormat:@"%d", ((int)messageParts.count)]] stringByAppendingString:@"_"] stringByAppendingString:encodedData]];
                    
                    [_webSocket send:aString];
                    
                    counter++;
                }
            }
        }
    }
}

- (void)subscribe:(NSString*) channel subscribeOnReconnected:(BOOL) aSubscribeOnReconnected onMessage:(void (^)(OrtcClient* ortc, NSString* channel, NSString* message)) onMessage
{
    
    [self subscribeChannel:channel WithNotifications:WITHOUT_NOTIFICATIONS subscribeOnReconnected:aSubscribeOnReconnected onMessage:onMessage];
}


- (void)subscribeWithNotifications:(NSString*) channel subscribeOnReconnected:(BOOL) aSubscribeOnReconnected onMessage:(void (^)(OrtcClient* ortc, NSString* channel, NSString* message)) onMessage
{
    [self subscribeChannel:channel WithNotifications:WITH_NOTIFICATIONS subscribeOnReconnected:aSubscribeOnReconnected onMessage:onMessage];
}



- (void)subscribeChannel:(NSString*) channel WithNotifications:(BOOL) withNotifications subscribeOnReconnected:(BOOL) aSubscribeOnReconnected onMessage:(void (^)(OrtcClient* ortc, NSString* channel, NSString* message)) onMessage
{
    if ([self checkChannelSubscription:channel WithNotifications:withNotifications]) {
        
        NSString* hashPerm = [self checkChannelPermissions:channel];
        if (!_permissions || (_permissions && hashPerm != nil)) {
            if (![_subscribedChannels objectForKey:channel]) {
                // Instantiate ChannelSubscription
                ChannelSubscription* channelSubscription = [[ChannelSubscription alloc] init];
                
                // Set channelSubscription properties
                channelSubscription.isSubscribing = YES;
                channelSubscription.isSubscribed = NO;
                channelSubscription.subscribeOnReconnected = aSubscribeOnReconnected;
                channelSubscription.onMessage = [onMessage copy];
                channelSubscription.withNotifications = withNotifications;
                // Add to subscribed channels dictionary
                [_subscribedChannels setObject:channelSubscription forKey:channel];
            }
            
            NSString* aString = nil;
            if (withNotifications) {
				if (![self isEmpty:[OrtcClient getDEVICE_TOKEN]]) {
					aString = [NSString stringWithFormat:@"\"subscribe;%@;%@;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm, [OrtcClient getDEVICE_TOKEN], PLATFORM];
				}
				else {
					[self delegateExceptionCallback:self error:[self generateError:@"Failed to register Device Token. Channel subscribed without Push Notifications"]];
					aString = [NSString stringWithFormat:@"\"subscribe;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm];
				}
			}
            else {
                aString = [NSString stringWithFormat:@"\"subscribe;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm];
            }
			//NSLog(@"SUB ON ORTC:\n%@",aString);
			if (![self isEmpty:aString]) {
				[_webSocket send:aString];
			}
		}
    }
}

- (void)unsubscribe:(NSString*) channel
{
    ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
    /*
     * Sanity Checks.
     */
    if (!isConnected) {
        [self delegateExceptionCallback:self error:[self generateError:@"Not connected"]];
    }
    else if ([self isEmpty:channel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Channel is null or empty"]];
    }
    else if (![self ortcIsValidInput:channel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Channel has invalid characters"]];
    }
    else if (!channelSubscription.isSubscribed) {
        [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Not subscribed to the channel %@", channel]]];
    }
    else {
        NSData* channelBytes = [NSData dataWithBytes:[channel UTF8String] length:[channel lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        
        if (channelBytes.length >= MAX_CHANNEL_SIZE) {
            [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Channel size exceeds the limit of %d characters", MAX_CHANNEL_SIZE]]];
        }
        else {
            NSString* aString = [[NSString alloc] init];
            if (channelSubscription.withNotifications) {
				if (![self isEmpty:[OrtcClient getDEVICE_TOKEN]]) {
					aString = [NSString stringWithFormat:@"\"unsubscribe;%@;%@;%@;%@\"", applicationKey, channel, [OrtcClient getDEVICE_TOKEN], PLATFORM];
				}
				else {
					aString = [NSString stringWithFormat:@"\"unsubscribe;%@;%@\"", applicationKey, channel];
				}
			}
            else {
                aString = [NSString stringWithFormat:@"\"unsubscribe;%@;%@\"", applicationKey, channel];
            }
			//NSLog(@"UNSUB ON ORTC:\n%@",aString);
			if (![self isEmpty:aString]) {
				[_webSocket send:aString];
			}
        }
    }
}

- (BOOL) checkChannelSubscription:(NSString *) channel WithNotifications:(BOOL) withNotifications
{
	ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
	/*
	 * Sanity Checks.
	 */
	if (!isConnected) {
		[self delegateExceptionCallback:self error:[self generateError:@"Not connected"]];
		return NO;
	}
	else if ([self isEmpty:channel]) {
		[self delegateExceptionCallback:self error:[self generateError:@"Channel is null or empty"]];
		return NO;
	}
	else if (withNotifications) {
		if (![self ortcIsValidChannelForMobile:channel]) {
			[self delegateExceptionCallback:self error:[self generateError:@"Channel has invalid characters"]];
			return NO;
		}
	}
	else if (![self ortcIsValidInput:channel]) {
		[self delegateExceptionCallback:self error:[self generateError:@"Channel has invalid characters"]];
		return NO;
	}
	else if (channelSubscription.isSubscribing) {
		[self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Already subscribing to the channel %@", channel]]];
		return NO;
	}
	else if (channelSubscription.isSubscribed) {
		[self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Already subscribed to the channel %@", channel]]];
		return NO;
	}
	else {
		NSData* channelBytes = [NSData dataWithBytes:[channel UTF8String] length:[channel lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
		
		if (channelBytes.length >= MAX_CHANNEL_SIZE) {
			[self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Channel size exceeds the limit of %d characters", MAX_CHANNEL_SIZE]]];
			return NO;
		}
	}
	return YES;
}


- (NSString *) checkChannelPermissions:(NSString *) channel
{
    unsigned long domainChannelIndex = (int)[channel rangeOfString:@":"].location;
    NSString* channelToValidate = channel;
    NSString* hashPerm = nil;
    
    if (domainChannelIndex != NSNotFound) {
        channelToValidate = [[channel substringToIndex:domainChannelIndex + 1] stringByAppendingString:@"*"];
    }
    
    if (_permissions) {
        hashPerm = [_permissions objectForKey:channelToValidate] ? [_permissions objectForKey:channelToValidate] : [_permissions objectForKey:channel];
        return hashPerm;
    }
    if (_permissions && !hashPerm) {
        [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"No permission found to subscribe to the channel '%@'", channel]]];
        return nil;
    }
    return hashPerm;
}


- (void)disconnect
{
    // Stop the connecting/reconnecting process
    stopReconnecting = YES;
    isConnecting = NO;
    isReconnecting = NO;
    hasConnectedFirstTime = NO;
    
    // Clear subscribed channels
    [_subscribedChannels removeAllObjects];
    
    /*
     * Sanity Checks.
     */
    if (!isConnected) {
        [self delegateExceptionCallback:self error:[self generateError:@"Not connected"]];
    }
    else {
        [self processDisconnect:YES];
    }
}

- (NSNumber*)isSubscribed:(NSString*) channel
{
    NSNumber* result = nil;
    
    /*
     * Sanity Checks.
     */
    if (!isConnected) {
        [self delegateExceptionCallback:self error:[self generateError:@"Not connected"]];
    }
    else if ([self isEmpty:channel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Channel is null or empty"]];
    }
    else if (![self ortcIsValidInput:channel]) {
        [self delegateExceptionCallback:self error:[self generateError:@"Channel has invalid characters"]];
    }
    else {
        result = [NSNumber numberWithBool:NO];
        
        ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
        
        result = channelSubscription.isSubscribed ? [NSNumber numberWithBool:YES] : [NSNumber numberWithBool:NO];
    }
    
    return result;
}

- (BOOL)saveAuthentication:(NSString*) aUrl isCLuster:(BOOL) aIsCluster authenticationToken:(NSString*) aAuthenticationToken authenticationTokenIsPrivate:(BOOL) aAuthenticationTokenIsPrivate applicationKey:(NSString*) aApplicationKey timeToLive:(int) aTimeToLive privateKey:(NSString*) aPrivateKey permissions:(NSMutableDictionary*) aPermissions
{
    /*
     * Sanity Checks.
     */
    if ([self isEmpty:aUrl]) {
        @throw [NSException exceptionWithName:@"Url" reason:@"URL is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aAuthenticationToken]) {
        @throw [NSException exceptionWithName:@"Authentication Token" reason:@"Authentication Token is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aApplicationKey]) {
        @throw [NSException exceptionWithName:@"Application Key" reason:@"Application Key is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aPrivateKey]) {
        @throw [NSException exceptionWithName:@"Private Key" reason:@"Private Key is null or empty" userInfo:nil];
    }
    else {
        BOOL ret = NO;
        
        NSString* connectionUrl = aUrl;
        
        if (aIsCluster) {
            connectionUrl = [[self getClusterServer:YES aPostUrl:aUrl] copy];
        }
        
        if (connectionUrl) {
            connectionUrl = [connectionUrl hasSuffix:@"/"] ? connectionUrl : [connectionUrl stringByAppendingString:@"/"];
            
            NSString* post = [NSString stringWithFormat:@"AT=%@&PVT=%@&AK=%@&TTL=%d&PK=%@", aAuthenticationToken, aAuthenticationTokenIsPrivate ? @"1" : @"0", aApplicationKey, aTimeToLive, aPrivateKey];
            
            if (aPermissions && aPermissions.count > 0) 
            {
                post = [post stringByAppendingString:[NSString stringWithFormat:@"&TP=%lu", (unsigned long)aPermissions.count]];
                
                NSArray* keys = [aPermissions allKeys]; // the dictionary keys
                
                for (NSString* key in keys) {
                    post = [post stringByAppendingString:[NSString stringWithFormat:@"&%@=%@", key, [aPermissions objectForKey:key]]];
                }
            }
            
            NSData* postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
            
            NSString* postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];
            
            NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
            
            [request setURL:[NSURL URLWithString:[connectionUrl stringByAppendingString:@"authenticate"]]];
            [request setHTTPMethod:@"POST"];
            [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            [request setHTTPBody:postData];
            
            // Send request and get response
            NSHTTPURLResponse* urlResponse = nil;
            NSError* error = nil;
            
            [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&error];
            
            ret = [urlResponse statusCode] == 201;
        }
        else {
            @throw [NSException exceptionWithName:@"Get Cluster URL" reason:@"Unable to get URL from cluster" userInfo:nil];
        }
        
        return ret;
    }
}


- (void)enablePresence:(NSString*) aUrl isCLuster:(BOOL) aIsCluster applicationKey:(NSString*) aApplicationKey privateKey:(NSString*) aPrivateKey channel:(NSString*) channel metadata:(BOOL) aMetadata callback:(void (^)(NSError* error, NSString* result)) aCallback
{
    /*
     * Sanity Checks.
     */
    if ([self isEmpty:aUrl]) {
        @throw [NSException exceptionWithName:@"Url" reason:@"URL is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aApplicationKey]) {
        @throw [NSException exceptionWithName:@"Application Key" reason:@"Application Key is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aPrivateKey]) {
        @throw [NSException exceptionWithName:@"Private Key" reason:@"Private Key is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:channel]) {
        @throw [NSException exceptionWithName:@"Channel" reason:@"Channel is null or empty" userInfo:nil];
    }
    else if (![self ortcIsValidInput:channel]) {
        @throw [NSException exceptionWithName:@"Channel" reason:@"Channel has invalid characters" userInfo:nil];
    }
    else {
        NSString* connectionUrl = aUrl;
        if (aIsCluster) {
            connectionUrl = [[self getClusterServer:YES aPostUrl:aUrl] copy];
        }        
        if (connectionUrl) {
            connectionUrl = [connectionUrl hasSuffix:@"/"] ? connectionUrl : [connectionUrl stringByAppendingString:@"/"];
            NSString* path = [NSString stringWithFormat:@"presence/enable/%@/%@", aApplicationKey, channel];
            connectionUrl = [connectionUrl stringByAppendingString:path];
            NSString* content = [NSString stringWithFormat:@"privatekey=%@&metadata=%@", aPrivateKey, (aMetadata ? @"1" : @"0")];            
            NSData* postData = [content dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
            NSString* postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];
            NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
            
            [request setURL:[NSURL URLWithString:connectionUrl]];
            [request setHTTPMethod:@"POST"];
            [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            [request setHTTPBody:postData];

            PresenceRequest *pr = [[PresenceRequest alloc] init];
            pr.callback = aCallback;
            [pr post:request];
        } else {
            NSError* error = [self generateError:@"Unable to get URL from cluster"];
            aCallback(error, nil);
        }
    }
}

- (void)disablePresence:(NSString*) aUrl isCLuster:(BOOL) aIsCluster applicationKey:(NSString*) aApplicationKey privateKey:(NSString*) aPrivateKey channel:(NSString*) channel callback:(void (^)(NSError* error, NSString* result)) aCallback
{
    /*
     * Sanity Checks.
     */
    if ([self isEmpty:aUrl]) {
        @throw [NSException exceptionWithName:@"Url" reason:@"URL is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aApplicationKey]) {
        @throw [NSException exceptionWithName:@"Application Key" reason:@"Application Key is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aPrivateKey]) {
        @throw [NSException exceptionWithName:@"Private Key" reason:@"Private Key is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:channel]) {
        @throw [NSException exceptionWithName:@"Channel" reason:@"Channel is null or empty" userInfo:nil];
    }
    else if (![self ortcIsValidInput:channel]) {
        @throw [NSException exceptionWithName:@"Channel" reason:@"Channel has invalid characters" userInfo:nil];
    }
    else {
        NSString* connectionUrl = aUrl;
        if (aIsCluster) {
            connectionUrl = [[self getClusterServer:YES aPostUrl:aUrl] copy];
        }
        if (connectionUrl) {
            connectionUrl = [connectionUrl hasSuffix:@"/"] ? connectionUrl : [connectionUrl stringByAppendingString:@"/"];
            NSString* path = [NSString stringWithFormat:@"presence/disable/%@/%@", aApplicationKey, channel];
            connectionUrl = [connectionUrl stringByAppendingString:path];
            NSString* content = [NSString stringWithFormat:@"privatekey=%@", aPrivateKey];
            NSData* postData = [content dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
            NSString* postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];
            NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
            
            [request setURL:[NSURL URLWithString:connectionUrl]];
            [request setHTTPMethod:@"POST"];
            [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            [request setHTTPBody:postData];
            
            PresenceRequest *pr = [[PresenceRequest alloc] init];
            pr.callback = aCallback;
            [pr post:request];
        } else {
            NSError* error = [self generateError:@"Unable to get URL from cluster"];
            aCallback(error, nil);
        }
    }
}

- (void)presence:(NSString*) aUrl isCLuster:(BOOL) aIsCluster applicationKey:(NSString*) aApplicationKey authenticationToken:(NSString*) aAuthenticationToken channel:(NSString*) channel callback:(void (^)(NSError* error, NSDictionary* result)) aCallback
{
    /*
     * Sanity Checks.
     */
    if ([self isEmpty:aUrl]) {
        @throw [NSException exceptionWithName:@"Url" reason:@"URL is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aApplicationKey]) {
        @throw [NSException exceptionWithName:@"Application Key" reason:@"Application Key is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:aAuthenticationToken]) {
        @throw [NSException exceptionWithName:@"Authentication Token" reason:@"Authentication Token is null or empty" userInfo:nil];
    }
    else if ([self isEmpty:channel]) {
        @throw [NSException exceptionWithName:@"Channel" reason:@"Channel is null or empty" userInfo:nil];
    }
    else if (![self ortcIsValidInput:channel]) {
        @throw [NSException exceptionWithName:@"Channel" reason:@"Channel has invalid characters" userInfo:nil];
    }
    else {
        NSString* connectionUrl = aUrl;
        if (aIsCluster) {
            connectionUrl = [[self getClusterServer:YES aPostUrl:aUrl] copy];
        }
        if (connectionUrl) {
            connectionUrl = [connectionUrl hasSuffix:@"/"] ? connectionUrl : [connectionUrl stringByAppendingString:@"/"];
            NSString* path = [NSString stringWithFormat:@"presence/%@/%@/%@", aApplicationKey, aAuthenticationToken, channel];
            connectionUrl = [connectionUrl stringByAppendingString:path];

            NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
            
            [request setURL:[NSURL URLWithString:connectionUrl]];
            [request setHTTPMethod:@"GET"];
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            
            PresenceRequest *pr = [[PresenceRequest alloc] init];
            pr.callbackDictionary = aCallback;
            [pr get:request];
        } else {
            NSError* error = [self generateError:@"Unable to get URL from cluster"];
            aCallback(error, nil);
        }
        
    }
}


- (int) getHeartbeatTime{
    return heartbeatTime;
}
- (void) setHeartbeatTime:(int) newHeartbeatTime {
    if(newHeartbeatTime > heartbeatMaxTime || newHeartbeatTime < heartbeatMinTime){
        [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Heartbeat time is out of limits (min: %d, max: %d)", heartbeatMinTime, heartbeatMaxTime]]];
    } else {
        heartbeatTime = newHeartbeatTime;
    }
}
- (int) getHeartbeatFails{
    return heartbeatFails;
}
- (void) setHeartbeatFails:(int) newHeartbeatFails {
    if(newHeartbeatFails > heartbeatMaxFails || newHeartbeatFails < heartbeatMinFails){
        [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Heartbeat fails is out of limits (min: %d, max: %d)", heartbeatMinFails, heartbeatMaxFails]]];
    } else {
        heartbeatFails = newHeartbeatFails;
    }
}
- (BOOL) isHeartbeatActive{
    return heartbeatActive;
}
- (void) enableHeartbeat{
    heartbeatActive = true;
}
- (void) disableHeartbeat{
    heartbeatActive = false;
}


static NSString *ortcDEVICE_TOKEN;
+ (void) setDEVICE_TOKEN:(NSString *) deviceToken {
    ortcDEVICE_TOKEN = deviceToken;
}

#pragma mark Private methods

- (void) startHeartbeatLoop{
    if(heartbeatTimer == nil && heartbeatActive)
        heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatTime target:self selector:@selector(heartbeatLoop) userInfo:nil repeats:YES];
}
- (void) stopHeartbeatLoop{
    if(heartbeatTimer != nil)
        [heartbeatTimer invalidate];
    heartbeatTimer = nil;
}
- (void) heartbeatLoop{
    if(heartbeatActive){
        [_webSocket send:@"\"b\""];
    } else {
        [self stopHeartbeatLoop];
    }
}

+ (NSString *) getDEVICE_TOKEN {
    return ortcDEVICE_TOKEN;
}

- (BOOL)ortcIsValidInput:(NSString*) input
{
    NSRegularExpression* opRegex = [NSRegularExpression regularExpressionWithPattern:@"^[\\w-:/.]*$" options:0 error:NULL];
    NSTextCheckingResult* opMatch = [opRegex firstMatchInString:input options:0 range:NSMakeRange(0, [input length])];
    
    return opMatch ? true : false;
}


- (BOOL)ortcIsValidChannelForMobile:(NSString*) input
{
    NSRegularExpression* opRegex = [NSRegularExpression regularExpressionWithPattern:@"^[\\w-:]*$" options:0 error:NULL];
    NSTextCheckingResult* opMatch = [opRegex firstMatchInString:input options:0 range:NSMakeRange(0, [input length])];
    
    return opMatch ? true : false;
}

- (BOOL)ortcIsValidUrl:(NSString*) input
{
    NSRegularExpression* opRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(http|https)://(\\w+:{0,1}\\w*@)?(\\S+)(:[0-9]+)?(/|/([\\w#!:.?+=&%@!\\-/]))?\\s*$" options:0 error:NULL];
    NSTextCheckingResult* opMatch = [opRegex firstMatchInString:input options:0 range:NSMakeRange(0, [input length])];
    
    return opMatch ? true : false;
}

- (BOOL)isEmpty:(id) thing
{
    return thing == nil
    || ([thing respondsToSelector:@selector(length)]
        && [(NSData*)thing length] == 0)
    || ([thing respondsToSelector:@selector(count)]
        && [(NSArray*)thing count] == 0);
}

- (NSError*)generateError:(NSString*) errText
{
    NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
    [errorDetail setValue:errText forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:@"OrtcClient" code:1 userInfo:errorDetail];
}

- (void)doConnect:(id) sender {
    if(heartbeatTimer != nil)
        [self stopHeartbeatLoop];

    if (isReconnecting) {
        [self delegateReconnectingCallback:self];
    }
    
    if (!stopReconnecting) {
        [self processConnect:self];
    }
}

- (void)parseReceivedMessage:(NSString*) aMessage
{
    if (aMessage)
    {
		if (![aMessage isEqualToString:@"o"] && ![aMessage isEqualToString:@"h"]) // Open and Heartbeat
        {
            //aMessage = [[aMessage stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""] stringByReplacingOccurrencesOfString:@"\\\\\\\\n" withString:@"\\n"];
            //NSRegularExpression* opTest = [NSRegularExpression regularExpressionWithPattern:TESTER options:0 error:NULL];
            //NSTextCheckingResult* opRES = [opTest firstMatchInString:aMessage options:0 range:NSMakeRange(0, [aMessage length])];
            
            NSRegularExpression* opRegex = [NSRegularExpression regularExpressionWithPattern:OPERATION_PATTERN options:0 error:NULL];
            NSTextCheckingResult* opMatch = [opRegex firstMatchInString:aMessage options:0 range:NSMakeRange(0, [aMessage length])];
            
            if (opMatch)
            {
                NSString* operation = nil;
                NSString* arguments = nil;
                
                NSRange strRangeOp = [opMatch rangeAtIndex:1];
                NSRange strRangeArgs = [opMatch rangeAtIndex:2];
                
                if (strRangeOp.location != NSNotFound) {
                    operation = [aMessage substringWithRange:strRangeOp];
                }
                
                if (strRangeArgs.location != NSNotFound) {
                    arguments = [aMessage substringWithRange:strRangeArgs];
                }
                
                if (operation) {
                    if ([opCases objectForKey:operation]) {
                        switch ([[opCases objectForKey:operation] intValue]) {
                            case opValidate:
                                if (arguments) {
                                    [self opValidated:arguments];
                                }
                                break;
                            case opSubscribe:
                                if (arguments) {
                                    [self opSubscribed:arguments];
                                }
                                break;
                            case opUnsubscribe:
                                if (arguments) {
                                    [self opUnsubscribed:arguments];
                                }
                                break;
                            case opException:
                                if (arguments) {
                                    [self opException:arguments];
                                }
                                break;
                            default:
                                [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Unknown message received: %@", aMessage]]];
                                break;
                        }
                    }
                }
                else {
                    [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Unknown message received: %@", aMessage]]];
                }
            }
            else {
                [self opReceive:aMessage];
            }
        }
    }
}

- (void)opValidated:(NSString*) message {    
    BOOL isValid = NO;
    
    NSRegularExpression* valRegex = [NSRegularExpression regularExpressionWithPattern:VALIDATED_PATTERN options:0 error:NULL];
    NSTextCheckingResult* valMatch = [valRegex firstMatchInString:message options:0 range:NSMakeRange(0, [message length])];
    
    if (valMatch)
    {
        isValid = YES;
        NSString* userPermissions = nil;
        
        NSRange strRangePerm = [valMatch rangeAtIndex:2];
        NSRange strRangeExpi = [valMatch rangeAtIndex:4];
        
        if (strRangePerm.location != NSNotFound) {
            userPermissions = [message substringWithRange:strRangePerm];
        }
        
        if (strRangeExpi.location != NSNotFound) {
            sessionExpirationTime = [[message substringWithRange:strRangeExpi] intValue];
        }
        
        if ([self isEmpty:[self readLocalStorage:[SESSION_STORAGE_NAME stringByAppendingString:applicationKey]]]) {
            [self createLocalStorage:[SESSION_STORAGE_NAME stringByAppendingString:applicationKey]];
        }
        
        // NOTE: userPermissions = null -> No authentication required for the application key
        if (userPermissions && ![userPermissions isEqualToString:@"null"]) {
            userPermissions = [userPermissions stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
            
            // Parse the string into JSON
            NSError* err = nil;
            NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:[userPermissions dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&err];
            
            if (err) {
               [self delegateExceptionCallback:self error:[self generateError:@"Error parsing the permissions received from server"]];
            }
            else {
                _permissions = [[NSMutableDictionary alloc] init];
                
                for (NSString* key in [dictionary allKeys]) {
                    // Add to permissions dictionary
                    [_permissions setValue:[dictionary objectForKey:key] forKey:key];
                }
            }
        }
    }
    
    if (isValid) {
        isConnecting = NO;
        isReconnecting = NO;
        isConnected = YES;
        
        if (hasConnectedFirstTime) {
            NSMutableArray* channelsToRemove = [[NSMutableArray alloc] init];
            
            // Subscribe to the previously subscribed channels
            for (NSString* channel in _subscribedChannels) {
                ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
                
                // Subscribe again
                if (channelSubscription.subscribeOnReconnected && (channelSubscription.isSubscribing || channelSubscription.isSubscribed)) {
                    channelSubscription.isSubscribing = YES;
                    channelSubscription.isSubscribed = NO;
                    
                    unsigned long domainChannelIndex = [channel rangeOfString:@":"].location;
                    NSString* channelToValidate = channel;
                    NSString* hashPerm = nil;
                    
                    if (domainChannelIndex != NSNotFound) {
                        channelToValidate = [[channel substringToIndex:domainChannelIndex + 1] stringByAppendingString:@"*"];
                    }
                    
                    if (_permissions) {
                        hashPerm = [_permissions objectForKey:channelToValidate] ? [_permissions objectForKey:channelToValidate] : [_permissions objectForKey:channel];
                    }
                    
                    NSString* aString = [[NSString alloc] init];
					aString = nil;
                    if (channelSubscription.withNotifications) {
						if (![self isEmpty:[OrtcClient getDEVICE_TOKEN]]) {
							aString = [NSString stringWithFormat:@"\"subscribe;%@;%@;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm, [OrtcClient getDEVICE_TOKEN], PLATFORM];
						}
						else {
							[self delegateExceptionCallback:self error:[self generateError:@"Failed to register Device Token. Channel subscribed without Push Notifications"]];
							aString = [NSString stringWithFormat:@"\"subscribe;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm];
						}
					}
                    else {
                        aString = [NSString stringWithFormat:@"\"subscribe;%@;%@;%@;%@\"", applicationKey, authenticationToken, channel, hashPerm];
                    }
					//NSLog(@"SUB ON ORTC:\n%@",aString);
					if (![self isEmpty:aString]) {
						[_webSocket send:aString];
					}
                }
                else {
                    [channelsToRemove addObject:channel];
                }
            }
            
            for (NSString* channel in channelsToRemove) {
                [_subscribedChannels removeObjectForKey:channel];
            }
            // Clean messages buffer (can have lost message parts in memory)
            [messagesBuffer removeAllObjects];
			[OrtcClient removeReceivedNotifications];
            [self delegateReconnectedCallback:self];
        }
        else {
            hasConnectedFirstTime = YES;
            
            [self delegateConnectedCallback:self];
        }
        [self startHeartbeatLoop];
    }
    else {
        [self disconnect];
        [self delegateExceptionCallback:self error:[self generateError:@"Invalid connection"]];
    }
}

- (void)opSubscribed:(NSString*) message {
    NSRegularExpression* subRegex = [NSRegularExpression regularExpressionWithPattern:CHANNEL_PATTERN options:0 error:NULL];
    NSTextCheckingResult* subMatch = [subRegex firstMatchInString:message options:0 range:NSMakeRange(0, [message length])];
    
    if (subMatch)
    {
        NSString* channel = nil;
        NSRange strRangeChn = [subMatch rangeAtIndex:1];
        
        if (strRangeChn.location != NSNotFound) {
            channel = [message substringWithRange:strRangeChn];
        }
        
        if (channel) {
            ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
            
            channelSubscription.isSubscribing = NO;
            channelSubscription.isSubscribed = YES;
            
            [self delegateSubscribedCallback:self channel:channel];
        }
    }
}

- (void)opUnsubscribed:(NSString*) message {
    NSRegularExpression* unsubRegex = [NSRegularExpression regularExpressionWithPattern:CHANNEL_PATTERN options:0 error:NULL];
    NSTextCheckingResult* unsubMatch = [unsubRegex firstMatchInString:message options:0 range:NSMakeRange(0, [message length])];
    
    if (unsubMatch)
    {
        NSString* channel = nil;
        NSRange strRangeChn = [unsubMatch rangeAtIndex:1];
        
        if (strRangeChn.location != NSNotFound) {
            channel = [message substringWithRange:strRangeChn];
        }
        
        if (channel) {
            [_subscribedChannels removeObjectForKey:channel];
            
            [self delegateUnsubscribedCallback:self channel:channel];
        }
    }
}

- (void)opException:(NSString*) message {                                                                                         
    NSRegularExpression* exRegex = [NSRegularExpression regularExpressionWithPattern:EXCEPTION_PATTERN options:0 error:NULL];
    NSTextCheckingResult* exMatch = [exRegex firstMatchInString:message options:0 range:NSMakeRange(0, [message length])];
    
    if (exMatch)
    {
        NSString* operation = nil;
        NSString* channel = nil;
        NSString* error = nil;
        
        NSRange strRangeOp = [exMatch rangeAtIndex:2];
        NSRange strRangeChn = [exMatch rangeAtIndex:4];
        NSRange strRangeErr = [exMatch rangeAtIndex:5];
        
        if (strRangeOp.location != NSNotFound) {
            operation = [message substringWithRange:strRangeOp];
        }
        
        if (strRangeChn.location != NSNotFound) {
            channel = [message substringWithRange:strRangeChn];
        }
        
        if (strRangeErr.location != NSNotFound) {
            error = [message substringWithRange:strRangeErr];
        }
        
        if (error) {
            if ([error isEqualToString:@"Invalid connection."]) {
                [self disconnect];
            }
            [self delegateExceptionCallback:self error:[self generateError:error]];
        }
        
        if (operation) {
            if ([errCases objectForKey:operation]) {
                switch ([[errCases objectForKey:operation] intValue]) {
                    case errValidate:
                        isConnecting = NO;
                        isReconnecting = NO;
                        
                        // Stop the connecting/reconnecting process
                        stopReconnecting = YES;
                        hasConnectedFirstTime = NO;
                        
                        [self processDisconnect:NO];
                        break;
                    case errSubscribe:
                        if (channel && [_subscribedChannels objectForKey:channel]) {
                            ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
                            
                            channelSubscription.isSubscribing = NO;
                        }
                        break;
                    case errSubscribeMaxSize:
                    case errUnsubscribeMaxSize:
                    case errSendMaxSize:
                        if (channel && [_subscribedChannels objectForKey:channel]) {
                            ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:channel];
                            
                            channelSubscription.isSubscribing = NO;
                        }
                        
                        // Stop the connecting/reconnecting process
                        stopReconnecting = YES;
                        hasConnectedFirstTime = NO;
                        
                        [self disconnect];
                        break;
                    default:
                        break;
                }
            }
        }
    }
}

- (void)opReceive:(NSString*) message {
    NSRegularExpression* recRegex = [NSRegularExpression regularExpressionWithPattern:RECEIVED_PATTERN options:0 error:NULL];
    NSTextCheckingResult* recMatch = [recRegex firstMatchInString:message options:0 range:NSMakeRange(0, [message length])];
    
    if (recMatch)
    {
        NSString* aChannel = nil;
        NSString* aMessage = nil;
        
        NSRange strRangeChn = [recMatch rangeAtIndex:1];
        NSRange strRangeMsg = [recMatch rangeAtIndex:2];
        
        if (strRangeChn.location != NSNotFound) {
            aChannel = [message substringWithRange:strRangeChn];
        }
        
        if (strRangeMsg.location != NSNotFound) {
            aMessage = [message substringWithRange:strRangeMsg];
        }
        
        if (aChannel && aMessage) {
            //aMessage = [[[aMessage stringByReplacingOccurrencesOfString:@"\\\\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\\\\\"" withString:@"\""] stringByReplacingOccurrencesOfString:@"\\\\\\\\" withString:@"\\"];
            
            // Multi part
            NSRegularExpression* msgRegex = [NSRegularExpression regularExpressionWithPattern:MULTI_PART_MESSAGE_PATTERN options:0 error:NULL];
            NSTextCheckingResult* multiMatch = [msgRegex firstMatchInString:aMessage options:0 range:NSMakeRange(0, [aMessage length])];
            
            NSString* messageId = nil;
            int messageCurrentPart = 1;
            int messageTotalPart = 1;
            BOOL lastPart = NO;
            
            if (multiMatch)
            {
                NSRange strRangeMsgId = [multiMatch rangeAtIndex:1];
                NSRange strRangeMsgCurPart = [multiMatch rangeAtIndex:2];
                NSRange strRangeMsgTotPart = [multiMatch rangeAtIndex:3];
                NSRange strRangeMsgRec = [multiMatch rangeAtIndex:4];
                
                if (strRangeMsgId.location != NSNotFound) {
                    messageId = [aMessage substringWithRange:strRangeMsgId];
                }
                
                if (strRangeMsgCurPart.location != NSNotFound) {
                    messageCurrentPart = [[aMessage substringWithRange:strRangeMsgCurPart] intValue];
                }
                
                if (strRangeMsgTotPart.location != NSNotFound) {
                    messageTotalPart = [[aMessage substringWithRange:strRangeMsgTotPart] intValue];
                }
                
                if (strRangeMsgRec.location != NSNotFound) {
                    aMessage = [aMessage substringWithRange:strRangeMsgRec];
                    //code below written by Rafa, gives a bug for a meesage containing % character
                    //aMessage = [[aMessage substringWithRange:strRangeMsgRec] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                }
            }
            // Is a message part
            if (![self isEmpty:messageId]) {
                if (![messagesBuffer objectForKey:messageId]) {
                    
                    NSMutableDictionary *msgSentDict = [[NSMutableDictionary alloc] init];
                    [msgSentDict setObject:[NSNumber numberWithBool:NO] forKey:@"isMsgSent"];
                    [messagesBuffer setObject:msgSentDict forKey:messageId];
                }
                
                NSMutableDictionary* messageBufferId = [messagesBuffer objectForKey:messageId];
                [messageBufferId setObject:aMessage forKey:[NSString stringWithFormat:@"%d", messageCurrentPart]];
                
                // Last message part -1 isMsgSent Key
                if (([[messageBufferId allKeys] count] -1) == messageTotalPart) {
                    lastPart = YES;
                }
            }
            // Message does not have multipart, like the messages received at announcement channels
            else {
                lastPart = YES;
            }
            
            if (lastPart) {
                if (![self isEmpty:messageId]) {
                    aMessage = @"";
                    NSMutableDictionary* messageBufferId = [messagesBuffer objectForKey:messageId];
                    
                    for (int i = 1; i <= messageTotalPart; i++) {
                        NSString* messagePart = [messageBufferId objectForKey:[NSString stringWithFormat:@"%d", i]];
                        
                        aMessage = [aMessage stringByAppendingString:messagePart];
                        // Delete from messages buffer
                        [messageBufferId removeObjectForKey:[NSString stringWithFormat:@"%d", i]];
                    }
				}
				
				if ([messagesBuffer objectForKey:messageId] && [[[messagesBuffer objectForKey:messageId] objectForKey:@"isMsgSent"] boolValue]) {
					[messagesBuffer removeObjectForKey:messageId];
				}
				else if ([_subscribedChannels objectForKey:aChannel]) {
                    ChannelSubscription* channelSubscription = [_subscribedChannels objectForKey:aChannel];
					
                    if (![self isEmpty:messageId]) {
						NSMutableDictionary *msgSentDict = [messagesBuffer objectForKey:messageId];
						[msgSentDict setObject:[NSNumber numberWithBool:YES] forKey:@"isMsgSent"];
						[messagesBuffer setObject:msgSentDict forKey:messageId];
					}
                    aMessage = [self escapeRecvChars:aMessage];
					channelSubscription.onMessage(self, aChannel, aMessage);
				}
            }
        }
    }
}

- (NSString*)escapeRecvChars:(NSString*) str{
    str = [self simulateJsonParse:str];
    str = [self simulateJsonParse:str];
    return str;
}
- (NSString*)simulateJsonParse:(NSString*) str{
    NSMutableString *ms = [NSMutableString string];
    for(int i =0; i < [str length]; i++){
        unichar ascii = [str characterAtIndex:i];
        if(ascii > 128){ //unicode
            [ms appendFormat:@"%@", [NSString stringWithCharacters:&ascii length:1]];
        } else { //ascii
            if(ascii == '\\'){
                i = i + 1;
                int next = [str characterAtIndex:i];
                if(next == '\\'){
                    [ms appendString:@"\\"];
                } else if(next == 'n'){
                    [ms appendString:@"\n"];
                } else if(next == '"'){
                    [ms appendString:@"\""];
                } else if(next == 'b'){
                    [ms appendString:@"\b"];
                } else if(next == 'f'){
                    [ms appendString:@"\f"];
                } else if(next == 'r'){
                    [ms appendString:@"\r"];
                } else if(next == 't'){
                    [ms appendString:@"\t"];
                } 
            } else {
                [ms appendFormat:@"%c", ascii];
            }
        }
    }
    return ms;
}

- (NSString*)generateId:(int) size
{
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef uuidStringRef = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    
    NSString *uuid = [NSString stringWithString:(__bridge NSString *) uuidStringRef];
    CFRelease(uuidStringRef);
    
    return [[[uuid stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:size] lowercaseString];
}

- (NSString*)randomString:(u_int32_t) size
{
    NSString* ret = @"";
    
    for (int i = 0; i < size; i++) {
        // A-Z
        NSString* letter = [NSString stringWithFormat:@"%0.1u", [self randomInRangeLo:65 toHi:90]];
        
        ret = [NSString stringWithFormat:@"%@%c", ret, (char)[letter intValue]];
    }
    
    return ret;
}

- (u_int32_t)randomInRangeLo:(u_int32_t) loBound toHi:(u_int32_t) hiBound
{
    u_int32_t random;
    int32_t range = hiBound - loBound + 1;
    
    u_int32_t limit = UINT32_MAX - (UINT32_MAX % range);
    
    do {
        random = arc4random();
    } while (random > limit);
    
    return loBound + (random % range);
}

- (void)processDisconnect:(BOOL) callDisconnectedCallback
{
    [self stopHeartbeatLoop];

    _webSocket.delegate = nil;
    [_webSocket close];
    
    if (callDisconnectedCallback) {
        [self delegateDisconnectedCallback:self];
    }
    
    isConnected = NO;
    isConnecting = NO;
    
    // Clear user permissions
    _permissions = nil;
}

- (void)processConnect:(id) sender
{
    if (!stopReconnecting) {
        /*
        if (isCluster) {
            url = [[self getClusterServer:NO aPostUrl:clusterUrl] copy];
            isCluster = YES;
        }*/
        
        (void)[[Balancer alloc] initWithCluster:clusterUrl serverUrl:url isCluster:isCluster appKey:applicationKey callback: ^(NSString* balancerResponse){
            url = balancerResponse;
            if(isCluster){
                if ([self isEmpty:balancerResponse]){
                    [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Unable to get URL from cluster (%@)", clusterUrl]]];
                }
            }
            if (url) {
                NSString* wsScheme = @"ws";
                NSDictionary* tlsSettings = nil;
                NSURL* connectionUrl  = [NSURL URLWithString:url];
                
                if ([connectionUrl.scheme isEqualToString:@"https"]) {
                    wsScheme = @"wss";
                    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    tlsSettings = [[NSDictionary alloc] initWithObjectsAndKeys:[NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates, [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot, [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain, kCFNull, kCFStreamSSLPeerName, kCFStreamSocketSecurityLevelSSLv3, kCFStreamSSLLevel, nil];
                }
                
                NSString* serverId = [NSString stringWithFormat:@"%0.3u", [self randomInRangeLo:1 toHi:1000]];
                NSString* connId = [self randomString:8];
                NSString* connUrl = connectionUrl.host;
                
                if (![self isEmpty:connectionUrl.port]) {
                    connUrl = [[connUrl stringByAppendingString:@":"] stringByAppendingString:[connectionUrl.port stringValue]];
                }
                
                NSString* wsUrl = [NSString stringWithFormat:@"%@://%@/broadcast/%@/%@/websocket", wsScheme, connUrl, serverId, connId];
                
                NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:wsUrl] cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval:5.0];
                _webSocket = [[RCTSRWebSocket alloc] initWithURLRequest:req];
                
                //_webSocket = [[RCTSRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:wsUrl]]];
                _webSocket.delegate = self;
               
                [_webSocket open];
              
            }
            else {
                [NSTimer scheduledTimerWithTimeInterval:connectionTimeout target:self selector:@selector(processConnect:) userInfo:nil repeats:NO];
            
            }
            
        }];
    }
}

- (NSDictionary*)readLocalStorage:(NSString*) sessionStorageName
{
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSString *plistPath;
    NSString *rootPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    plistPath = [rootPath stringByAppendingPathComponent:@"OrtcClient.plist"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
        plistPath = [[NSBundle mainBundle] pathForResource:@"OrtcClient" ofType:@"plist"];
    }
    
    //NSLog(@"plistPath: %@", plistPath);
    
    NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
    NSDictionary *plistProps = (NSDictionary *)[NSPropertyListSerialization propertyListFromData:plistXML mutabilityOption:NSPropertyListMutableContainersAndLeaves format:&format errorDescription:&errorDesc];
    
    if (plistProps) {
        //[self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Error reading plist: %@, format: %d", errorDesc, format]]];
        
        if ([plistProps objectForKey:@"sessionCreatedAt"]) {
            sessionCreatedAt = [plistProps objectForKey:@"sessionCreatedAt"];
        }
        
        NSDate* currentDateTime = [NSDate date];
        NSTimeInterval time = [currentDateTime timeIntervalSinceDate:sessionCreatedAt];
        int minutes = time / 60;
        
        if (minutes >= sessionExpirationTime) {
            plistProps = nil;
        }
        else if ([plistProps objectForKey:@"sessionId"]) {
            sessionId = [plistProps objectForKey:@"sessionId"];
        }
    }
    
    return plistProps;
}

- (void)createLocalStorage:(NSString*) sessionStorageName
{
    sessionCreatedAt = [NSDate date];
    
    NSArray *keys = [NSArray arrayWithObjects:@"sessionId", @"sessionCreatedAt", nil];
    NSArray *objects = [NSArray arrayWithObjects:sessionId, sessionCreatedAt, nil];
    NSDictionary* sessionInfo = [NSDictionary dictionaryWithObjects:objects forKeys:keys];
    
    NSString *error;
    NSString *rootPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *plistPath = [rootPath stringByAppendingPathComponent:@"OrtcClient.plist"];
    NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:sessionInfo format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
    
    if (plistData) {
        [plistData writeToFile:plistPath atomically:YES];
    }
    else {
        [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Error : %@", error]]];
    }
}

- (NSString*)getClusterServer:(BOOL) isPostingAuth aPostUrl:(NSString *) postUrl
{
    NSString* result = nil;
    NSString* parsedUrl = postUrl;
    
    if(applicationKey != NULL)
    {
        parsedUrl = [parsedUrl stringByAppendingString:@"?appkey="];
        parsedUrl = [parsedUrl stringByAppendingString:applicationKey];
    }
    
    // Initiate connection
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:parsedUrl]];
    
    // Send request and get response
    NSData* response = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    
    NSString* myString = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    
    NSRegularExpression* resRegex = [NSRegularExpression regularExpressionWithPattern:CLUSTER_RESPONSE_PATTERN options:0 error:NULL];
    NSTextCheckingResult* resMatch = [resRegex firstMatchInString:myString options:0 range:NSMakeRange(0, [myString length])];
    
    if (resMatch)
    {
        NSRange strRange = [resMatch rangeAtIndex:1];
        
        if (strRange.location != NSNotFound) {
            result = [myString substringWithRange:strRange];
        }
    }
    
    if (!isPostingAuth) 
    {
        if ([self isEmpty:result])
        {
            [self delegateExceptionCallback:self error:[self generateError:[NSString stringWithFormat:@"Unable to get URL from cluster (%@)", parsedUrl]]];
        }
    }
        
    return result;
}

#pragma mark - RCTSRWebSocketDelegate

- (void)webSocket:(RCTSRWebSocket*) webSocket didReceiveMessage:(id) aMessage
{
    [self parseReceivedMessage:aMessage];
}

- (void)webSocketDidOpen:(RCTSRWebSocket *)webSocket
{
    if ([self isEmpty:[self readLocalStorage:[SESSION_STORAGE_NAME stringByAppendingString:applicationKey]]]) {
        sessionId = [self generateId:16];
    }
    //Heartbeat details
    NSString *hbDetails = @"";
    if(heartbeatActive){
        hbDetails = [NSString stringWithFormat:@";%d;%d;", heartbeatTime, heartbeatFails];
    }
    // Send validate
    NSString* aString = [NSString stringWithFormat:@"\"validate;%@;%@;%@;%@;%@%@\"", applicationKey, authenticationToken, announcementSubChannel ? announcementSubChannel : @"", sessionId ? sessionId : @"", connectionMetadata ? connectionMetadata : @"", hbDetails];
    
    [_webSocket send:aString];
}

- (void)webSocket:(RCTSRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    isConnecting = NO;
	
	// Reconnect
    if (!stopReconnecting) {
        isConnecting = YES;
        stopReconnecting = NO;
        
        if (!isReconnecting) {
            isReconnecting = YES;
            if(isCluster){
                NSURL *tUrl = [NSURL URLWithString:clusterUrl];
                if ([tUrl.scheme isEqualToString:@"http"] && doFallback) {
                    NSString *t = [clusterUrl stringByReplacingOccurrencesOfString:@"http:" withString:@"https:"];
                    NSRange r = [t rangeOfString:@"/server/ssl/"];
                    if(r.location == NSNotFound){
                        clusterUrl = [t stringByReplacingOccurrencesOfString:@"/server/" withString:@"/server/ssl/"];
                    } else {
                        clusterUrl = t;
                    }
                }
            }
            [self doConnect:self];
        }
        else {

            [NSTimer scheduledTimerWithTimeInterval:connectionTimeout target:self selector:@selector(doConnect:) userInfo:nil repeats:NO];
        }
    }
}

- (void)webSocket:(RCTSRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    [self processDisconnect:YES];
    
    // Reconnect
    if (!stopReconnecting) {
        isConnecting = YES;
        stopReconnecting = NO;
        
        if (!isReconnecting) {
            isReconnecting = YES;
            
            [self doConnect:self];
        }
        else {
            [NSTimer scheduledTimerWithTimeInterval:connectionTimeout target:self selector:@selector(doConnect:) userInfo:nil repeats:NO];
        }
    }
}

#pragma mark Lifecycle

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopHeartbeatLoop];
}

+ (id)ortcClientWithConfig:(id<OrtcClientDelegate>) aDelegate
{
    return [[[self class] alloc] initWithConfig:aDelegate];
}

- (id)initWithConfig:(id<OrtcClientDelegate>) aDelegate
{
    self = [super init];
    
    if (self) {
        if (opCases == nil) {
            opCases = [[NSMutableDictionary alloc] initWithCapacity:4];
            
            [opCases setObject:[NSNumber numberWithInt:opValidate] forKey:@"ortc-validated"];
            [opCases setObject:[NSNumber numberWithInt:opSubscribe] forKey:@"ortc-subscribed"];
            [opCases setObject:[NSNumber numberWithInt:opUnsubscribe] forKey:@"ortc-unsubscribed"];
            [opCases setObject:[NSNumber numberWithInt:opException] forKey:@"ortc-error"];
        }
        
        if (errCases == nil) {
            errCases = [[NSMutableDictionary alloc] initWithCapacity:5];
            
            [errCases setObject:[NSNumber numberWithInt:errValidate] forKey:@"validate"];
            [errCases setObject:[NSNumber numberWithInt:errSubscribe] forKey:@"subscribe"];
            [errCases setObject:[NSNumber numberWithInt:errSubscribeMaxSize] forKey:@"subscribe_maxsize"];
            [errCases setObject:[NSNumber numberWithInt:errUnsubscribeMaxSize] forKey:@"unsubscribe_maxsize"];
            [errCases setObject:[NSNumber numberWithInt:errSendMaxSize] forKey:@"send_maxsize"];
        }
        
        //apply properties
        _ortcDelegate = aDelegate;
        
        connectionTimeout = 5; // seconds
        sessionExpirationTime = 30; // minutes
        
        isConnected = NO;
        isConnecting = NO;
        isReconnecting = NO;
        hasConnectedFirstTime = NO;
        doFallback = YES;
        
        _permissions = nil;
        
        _subscribedChannels = [[NSMutableDictionary alloc] init];
        messagesBuffer = [[NSMutableDictionary alloc] init];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedNotification:) name:@"ApnsNotification" object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedNotification:) name:@"ApnsRegisterError" object:nil];
        
        heartbeatTime = heartbeatDefaultTime; // Heartbeat interval time
        heartbeatFails = heartbeatDefaultFails; // Heartbeat max fails
        heartbeatTimer = nil;
        heartbeatActive = false;
	}
    return self;
}



- (void) receivedNotification:(NSNotification *) notification
{
    // [notification name] should be @"ApnsNotification" for received Apns Notififications
    if ([[notification name] isEqualToString:@"ApnsNotification"]) {		
		NSDictionary *notificaionInfo = [[NSDictionary alloc] initWithDictionary:[notification userInfo]];
		if ([[notificaionInfo objectForKey:@"A"] isEqualToString:applicationKey]) {
			
			NSString *ortcMessage = [NSString stringWithFormat:@"a[\"{\\\"ch\\\":\\\"%@\\\",\\\"m\\\":\\\"%@\\\"}\"]", [notificaionInfo objectForKey:@"C"], [notificaionInfo objectForKey:@"M"]];
			[self parseReceivedMessage:ortcMessage];
		}
	}
	
	// [notification name] should be @"ApnsRegisterError" if an error ocured on RegisterForRemoteNotifications
	if ([[notification name] isEqualToString:@"ApnsRegisterError"]) {
		[self delegateExceptionCallback:self error:[[notification userInfo] objectForKey:@"ApnsRegisterError"]];
	}
}


- (void) parseReceivedNotifications {
	
	NSMutableDictionary *notificationsDict = [[NSMutableDictionary alloc] initWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:NOTIFICATIONS_KEY]];
	NSMutableArray *receivedMessages = [[NSMutableArray alloc] initWithArray:[notificationsDict objectForKey:applicationKey]];
	//NSMutableArray *messages = [[NSMutableArray alloc] initWithArray:receivedMessages];
	
	for (NSString *message in receivedMessages) {
		[self parseReceivedMessage:message];
		//[receivedMessages removeObject:message];
	}
	[receivedMessages removeAllObjects];
	
	[notificationsDict setObject:receivedMessages forKey:applicationKey];
	[[NSUserDefaults standardUserDefaults] setObject:notificationsDict forKey:NOTIFICATIONS_KEY];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void) removeReceivedNotifications {
	
	NSMutableDictionary *notificationsDict = [[NSMutableDictionary alloc] initWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:NOTIFICATIONS_KEY]];
	[notificationsDict removeAllObjects];
	
	[[NSUserDefaults standardUserDefaults] setObject:notificationsDict forKey:NOTIFICATIONS_KEY];
	[[NSUserDefaults standardUserDefaults] synchronize];
}


#pragma mark Callbacks

/*
 * Calls the onConnected callback if defined.
 */
- (void)delegateConnectedCallback:(OrtcClient*) ortc {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onConnected:)])
    {
        [_ortcDelegate performSelector: @selector(onConnected:) withObject:ortc];
        [self parseReceivedNotifications];
	}
}

/*
 * Calls the onDisconnected callback if defined.
 */
- (void)delegateDisconnectedCallback:(OrtcClient*) ortc {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onDisconnected:)])
    {
        [_ortcDelegate performSelector: @selector(onDisconnected:) withObject:ortc];
	}
}

/*
 * Calls the onSubscribed callback if defined.
 */
- (void)delegateSubscribedCallback:(OrtcClient*) ortc channel:(NSString*) channel {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onSubscribed:channel:)])
    {
        [_ortcDelegate performSelector: @selector(onSubscribed:channel:) withObject:ortc withObject:channel];
    }
}

/*
 * Calls the onUnsubscribed callback if defined.
 */
- (void)delegateUnsubscribedCallback:(OrtcClient*) ortc channel:(NSString*) channel {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onUnsubscribed:channel:)])
    {
        [_ortcDelegate performSelector: @selector(onUnsubscribed:channel:) withObject:ortc withObject:channel];
    }
}

/*
 * Calls the onException callback if defined.
 */
- (void)delegateExceptionCallback:(OrtcClient*) ortc error:(NSError*) aError {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onException:error:)])
    {
        [_ortcDelegate performSelector: @selector(onException:error:) withObject:ortc withObject:aError];
    }
}

/*
 * Calls the onReconnecting callback if defined.
 */
- (void)delegateReconnectingCallback:(OrtcClient*) ortc {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onReconnecting:)])
    {
        [_ortcDelegate performSelector: @selector(onReconnecting:) withObject: ortc];
    }
}

/*
 * Calls the onReconnected callback if defined.
 */
- (void)delegateReconnectedCallback:(OrtcClient*) ortc {
    if (_ortcDelegate != nil && [_ortcDelegate respondsToSelector: @selector(onReconnected:)])
    {
        [_ortcDelegate performSelector: @selector(onReconnected:) withObject: ortc];
		[self parseReceivedNotifications];
	}
}


@end

@implementation ChannelSubscription

@synthesize isSubscribing;
@synthesize isSubscribed;
@synthesize subscribeOnReconnected;
@synthesize withNotifications;
@synthesize onMessage;

- (id)init {
	if (self=[super init]) {
		//do something here
	}
    
	return self;
}

@end


@implementation PresenceRequest

@synthesize receivedData;
@synthesize isResponseJSON;

- init {
    if ((self = [super init])) {
 		
    }
    return self;
}

- (void)get: (NSMutableURLRequest *)request {
    self.isResponseJSON = true;
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue new] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        
        NSString *dataStr=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if(self.isResponseJSON){
            NSError* err = nil;
            NSDictionary* dictionary = nil;
            dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            
            if (err) {
                if([dataStr caseInsensitiveCompare:@"null"] != NSOrderedSame ) {
                    NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
                    [errorDetail setValue:dataStr forKey:NSLocalizedDescriptionKey];
                    NSError* error = [NSError errorWithDomain:@"OrtcClient" code:1 userInfo:errorDetail];
                    self.callbackDictionary(error, nil);
                } else {
                    self.callbackDictionary(nil, (NSDictionary*)@"null");
                }
            } else {
                self.callbackDictionary(nil, dictionary);
            }
        } else {
            self.callback(nil, dataStr);
        }
    }];

// 	NSURLConnection* ret = [[NSURLConnection alloc] initWithRequest:request delegate:self];
//    if (ret == nil){
//        NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
//        [errorDetail setValue:@"The connection can't be initialized." forKey:NSLocalizedDescriptionKey];
//        NSError* error = [NSError errorWithDomain:@"OrtcClient" code:1 userInfo:errorDetail];
//        if(self.isResponseJSON)
//            self.callbackDictionary(error, nil);
//        else
//            self.callback(error, nil);
//    }
}

- (void)post: (NSMutableURLRequest *)request{
    self.isResponseJSON = false;
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue new] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        
        NSString *dataStr=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if(self.isResponseJSON){
            NSError* err = nil;
            NSDictionary* dictionary = nil;
            dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            
            if (err) {
                if([dataStr caseInsensitiveCompare:@"null"] != NSOrderedSame ) {
                    NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
                    [errorDetail setValue:dataStr forKey:NSLocalizedDescriptionKey];
                    NSError* error = [NSError errorWithDomain:@"OrtcClient" code:1 userInfo:errorDetail];
                    self.callbackDictionary(error, nil);
                } else {
                    self.callbackDictionary(nil, (NSDictionary*)@"null");
                }
            } else {
                self.callbackDictionary(nil, dictionary);
            }
        } else {
            self.callback(nil, dataStr);
        }
    }];
    
// 	NSURLConnection* ret = [[NSURLConnection alloc] initWithRequest:request delegate:self];
//    if (ret == nil){
//        NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
//        [errorDetail setValue:@"The connection can't be initialized." forKey:NSLocalizedDescriptionKey];
//        NSError* error = [NSError errorWithDomain:@"OrtcClient" code:1 userInfo:errorDetail];
//        if(self.isResponseJSON)
//            self.callbackDictionary(error, nil);
//        else
//            self.callback(error, nil);
//    }
}

#pragma mark NSURLConnection delegate methods
- (NSURLRequest *)connection:(NSURLConnection *)connection
 			 willSendRequest:(NSURLRequest *)request
 			redirectResponse:(NSURLResponse *)redirectResponse {
    return request;
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if(self.isResponseJSON)
        self.callbackDictionary(error, nil);
    else
        self.callback(error, nil);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
 	NSString *dataStr=[[NSString alloc] initWithData:self.receivedData encoding:NSUTF8StringEncoding];
    if(self.isResponseJSON){
        NSError* err = nil;
        NSDictionary* dictionary = nil;
        dictionary = [NSJSONSerialization JSONObjectWithData:[dataStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&err];

        if (err) {
            if([dataStr caseInsensitiveCompare:@"null"] != NSOrderedSame ) {
                NSMutableDictionary* errorDetail = [NSMutableDictionary dictionary];
                [errorDetail setValue:dataStr forKey:NSLocalizedDescriptionKey];
                NSError* error = [NSError errorWithDomain:@"OrtcClient" code:1 userInfo:errorDetail];
                self.callbackDictionary(error, nil);
            } else {
                self.callbackDictionary(nil, (NSDictionary*)@"null");
            }
        } else {
            self.callbackDictionary(nil, dictionary);
        }
    } else {
        self.callback(nil, dataStr);
    }
}

@end

