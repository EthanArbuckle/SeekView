//
//  SeekDeviceDiscovery.h
//  SeekConnect
//
//  Created by Ethan Arbuckle on 12/8/23.
//

#import "SeekDevice.h"
#import "seek.h"
#import <Foundation/Foundation.h>
#import <libusb.h>

NS_ASSUME_NONNULL_BEGIN

@interface SeekDeviceDiscovery : NSObject

@property (nonatomic) BOOL isDiscovering;

+ (id)discoverer;
- (void)addDiscoveryHandler:(void (^)(SeekDevice *device))discoveryHandler;
- (void)startDiscovery;
- (void)stopDiscovery;

@end

NS_ASSUME_NONNULL_END
