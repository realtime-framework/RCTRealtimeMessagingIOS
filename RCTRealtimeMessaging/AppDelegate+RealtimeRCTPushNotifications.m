//
//  AppDelegate+RealtimeRCTPushNotifications.m
//  RCTRealtimeMessaging
//
//  Created by Joao Caixinha on 07/09/15.
//  Copyright (c) 2015 Realtime. All rights reserved.
//

#import "AppDelegate+RealtimeRCTPushNotifications.h"
#import <objc/runtime.h>
#define NOTIFICATIONS_KEY @"Local_Storage_Notifications"

#pragma GCC diagnostic ignored "-Wundeclared-selector"
@implementation AppDelegate (RealtimeRCTPushNotifications)


+ (void)load
{
    [[NSNotificationCenter defaultCenter] addObserver:[self class] selector:@selector(registForNotifications) name:UIApplicationDidFinishLaunchingNotification object:nil];
}


+ (BOOL)registForNotifications
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    } else {
        [[UIApplication sharedApplication] registerForRemoteNotificationTypes: UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge];
    }
#else
    [application registerForRemoteNotificationTypes: UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge];
#endif
    
    return YES;
}



- (void)application:(UIApplication *)application
didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
  NSString* newToken = [deviceToken description];
  newToken = [newToken stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
  newToken = [newToken stringByReplacingOccurrencesOfString:@" " withString:@""];
  NSLog(@"\n\n - didRegisterForRemoteNotificationsWithDeviceToken:\n%@\n", deviceToken);
  
  id ortc = NSClassFromString (@"OrtcClient");
  if ([ortc respondsToSelector:@selector(setDEVICE_TOKEN:)]) {
    [ortc performSelector:@selector(setDEVICE_TOKEN:) withObject:[[NSString alloc] initWithString:newToken]];
  }
}


- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
  [self application:application didReceiveRemoteNotification:userInfo];
  completionHandler(UIBackgroundFetchResultNewData);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
  if ([userInfo objectForKey:@"C"] && [userInfo objectForKey:@"M"] && [userInfo objectForKey:@"A"]) {
    
    if ([[[userInfo objectForKey:@"aps" ] objectForKey:@"alert"] isKindOfClass:[NSString class]]) {
      NSString *ortcMessage = [NSString stringWithFormat:@"a[\"{\\\"ch\\\":\\\"%@\\\",\\\"m\\\":\\\"%@\\\"}\"]", [userInfo objectForKey:@"C"], [userInfo objectForKey:@"M"]];
      
      NSMutableDictionary *notificationsDict  = [[NSMutableDictionary alloc] initWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:NOTIFICATIONS_KEY]];
      NSMutableArray *notificationsArray = [[NSMutableArray alloc] initWithArray:[notificationsDict objectForKey:[userInfo objectForKey:@"A"]]];
      [notificationsArray addObject:ortcMessage];
      [notificationsDict setObject:notificationsArray forKey:[userInfo objectForKey:@"A"]];
      
      [[NSUserDefaults standardUserDefaults] setObject:notificationsDict forKey:NOTIFICATIONS_KEY];
      [[NSUserDefaults standardUserDefaults] synchronize];
      
      [[NSNotificationCenter defaultCenter] postNotificationName:@"ApnsNotification" object:nil userInfo:userInfo];
      
    }else{
      
      [[NSNotificationCenter defaultCenter] postNotificationName:@"Notification" object:nil userInfo:userInfo];
      
    }
  }
}


- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
  NSLog(@"Failed to register with error : %@", error);
  
  [[NSNotificationCenter defaultCenter] postNotificationName:@"ApnsRegisterError" object:nil userInfo:[NSDictionary dictionaryWithObject:error forKey:@"ApnsRegisterError"]];
}





@end
