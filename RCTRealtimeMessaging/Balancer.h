//
//  Balancer.h
//  OrtcClient
//
//  Created by Marcin Kulwikowski on 15/07/14.
//
//

#import <Foundation/Foundation.h>

@interface Balancer : NSObject

- initWithCluster:(NSString*) aCluster serverUrl:(NSString*)url isCluster:(BOOL)isCluster appKey:(NSString*) anAppKey callback:(void (^)(NSString *aBalancerResponse))aCallback;

@end
