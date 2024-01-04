//
//  SeekDeviceDiscovery.m
//  SeekConnect
//
//  Created by Ethan Arbuckle on 12/8/23.
//

#import "SeekDeviceDiscovery.h"
#import <libusb.h>
#import "SeekDeviceS104SP.h"


@interface SeekDeviceDiscovery () {
    
    NSMutableArray *discoveryHandlers;
    dispatch_queue_t device_discovery_queue;
    libusb_context *libusb_ctx;
}

- (void)_handleCallbackForS104SP:(libusb_device *)usb_device;

@end

void usb_callback_s104sp(libusb_context *ctx, libusb_device *usb_device, libusb_hotplug_event event, void *user_data) {
    
    debug_log("discoverer found a new s104sp device %p\n", usb_device);
    [[SeekDeviceDiscovery discoverer] _handleCallbackForS104SP:usb_device];
}

@implementation SeekDeviceDiscovery

- (id)init {

    [[NSException exceptionWithName:@"SeekDeviceDiscovery" reason:@"Use +discoverer intead of -init" userInfo:nil] raise];
    return nil;
}

+ (id)discoverer {
    
    static dispatch_once_t onceToken;
    static SeekDeviceDiscovery *sharedDiscoverer;
    dispatch_once(&onceToken, ^{
        sharedDiscoverer = [[SeekDeviceDiscovery alloc] _initShared];
    });
    
    if (!sharedDiscoverer) {
        debug_log("cannot proceed with without a discoverer\n");
        [[NSException exceptionWithName:@"SeekDeviceDiscovery" reason:@"Failed to create a device discoverer. Check libusb" userInfo:nil] raise];
    }
    
    return sharedDiscoverer;
}

- (id)_initShared {
    
    if ((self = [super init])) {
        
        self->discoveryHandlers = [[NSMutableArray alloc] init];
        self->device_discovery_queue = dispatch_queue_create("com.ea.device.finder", 0);
        self.isDiscovering = NO;
        
        
        if (libusb_init(&libusb_ctx) < 0) {
            debug_log("libusb_init context failed\n");
            return nil;
        }
    }
    
    return self;
}


- (void)addDiscoveryHandler:(void (^)(SeekDevice *device))discoveryHandler {
    
    [self->discoveryHandlers addObject:discoveryHandler];
}

- (void)startDiscovery {
    
    if (self.isDiscovering) {
        return;
    }
    
    self.isDiscovering = YES;
    libusb_hotplug_register_callback(self->libusb_ctx, LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED, LIBUSB_HOTPLUG_ENUMERATE, S104SP_USB_VENDOR_ID, S104SP_USB_PRODUCT_ID, LIBUSB_HOTPLUG_MATCH_ANY, (libusb_hotplug_callback_fn)usb_callback_s104sp, NULL, NULL);
}

- (void)stopDiscovery {
    
    self.isDiscovering = NO;
}

- (void)_handleCallbackForS104SP:(libusb_device *)usb_device {
    
    libusb_device_handle *device_handle = NULL;
    if (libusb_open(usb_device, &device_handle) != LIBUSB_SUCCESS) {
        debug_log("libusb_open failed. Not notifying listeners\n");
        return;
    }
    
    SeekDevice *camera = [[SeekDeviceS104SP alloc] initWithDeviceHandle:device_handle delegate:nil];
    if (!camera) {
        debug_log("Camera creation failed. Not notifying listeners\n");
        return;
    }
    
    // Notify handlers
    for (void (^discoveryHandler)(SeekDevice *device) in self->discoveryHandlers) {
        discoveryHandler(camera);
    }
}

@end
