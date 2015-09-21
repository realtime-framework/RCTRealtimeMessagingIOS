//
//  AppDelegate+RealtimeRCTPushNotifications.h
//  RCTRealtimeMessaging
//
//  Created by Joao Caixinha on 07/09/15.
//  Copyright (c) 2015 Realtime. All rights reserved.
//
#import "AppDelegate.h"


@interface AppDelegate (RealtimeRCTPushNotifications)

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo;

@end
