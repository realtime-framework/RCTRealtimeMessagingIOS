//
//  Balancer.m
//  OrtcClient
//
//  Created by Marcin Kulwikowski on 15/07/14.
//
//

#import "Balancer.h"

NSString* const BALANCER_RESPONSE_PATTERN = @"^var SOCKET_SERVER = \\\"(.*?)\\\";$";

@implementation Balancer {
    NSMutableData *receivedData;
    void (^theCallabck)(NSString*);
}


- (id) initWithCluster:(NSString*) aCluster serverUrl:(NSString*)url isCluster:(BOOL)isCluster appKey:(NSString*) anAppKey callback:(void (^)(NSString *aBalancerResponse))aCallback{
    if ((self = [super init])) {
        theCallabck = aCallback;
        NSString* parsedUrl = aCluster;
        
        if(!isCluster){
            aCallback(url);
        } else {
            if(anAppKey != NULL){
                parsedUrl = [parsedUrl stringByAppendingString:@"?appkey="];
                parsedUrl = [parsedUrl stringByAppendingString:anAppKey];
            }

            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:parsedUrl]];
            //(void)[[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
            
           [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue new] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
               if(data !=nil){
                   NSString* myString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                   
                   NSRegularExpression* resRegex = [NSRegularExpression regularExpressionWithPattern:BALANCER_RESPONSE_PATTERN options:0 error:NULL];
                   NSTextCheckingResult* resMatch = [resRegex firstMatchInString:myString options:0 range:NSMakeRange(0, [myString length])];
                   if (resMatch)
                   {
                       NSRange strRange = [resMatch rangeAtIndex:1];
                       
                       if (strRange.location != NSNotFound) {
                           theCallabck([myString substringWithRange:strRange]);
                           return;
                       }
                   }
               }
               theCallabck(nil);
           }];
        }
    }

    return nil;
}

@end
