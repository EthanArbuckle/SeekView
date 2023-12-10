//
//  SeekDeviceDiscovery.h
//  SeekConnect
//
//  Created by Ethan Arbuckle on 12/8/23.
//

#import "SeekMosaicCamera.h"
#import "seek.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeekDeviceDiscovery : NSObject

@property (nonatomic) BOOL isDiscovering;

- (void)addDiscoveryHandler:(void (^)(SeekMosaicCamera *device))discoveryHandler;
- (void)startDiscovery;
- (void)stopDiscovery;
- (void)_notifyHandlersOfDevice:(void *)dev;

@end

NS_ASSUME_NONNULL_END
