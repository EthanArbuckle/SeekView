//
//  SeekDeviceDiscovery.m
//  SeekConnect
//
//  Created by Ethan Arbuckle on 12/8/23.
//

#import "SeekDeviceDiscovery.h"
#import <libusb.h>


@interface SeekDeviceDiscovery () {
    
    NSMutableArray *discoveryHandlers;
    dispatch_queue_t device_discovery_queue;
    libusb_context *libusb_ctx;
}

@end

SeekDeviceDiscovery *omgHack = nil;

void callback_function(libusb_context *ctx, libusb_device *device, libusb_hotplug_event event, void *user_data) {
    
    debug_log("found a new device %p\n", device);

    libusb_device_handle *dev = NULL;
    if (libusb_open(device, &dev) != LIBUSB_SUCCESS) {
        debug_log("libusb_open failed\n");
        return;
    }
    
    if (libusb_kernel_driver_active(dev, 0) && libusb_detach_kernel_driver(dev, 0) < 0) {
        debug_log("libusb_detach_kernel_driver failed\n");
        libusb_close(dev);
        return;
    }
    
    if (libusb_set_configuration(dev, 1) < 0) {
        debug_log("libusb_set_configuration failed\n");
        libusb_close(dev);
        return;
    }

    debug_log("attempting to connect to the device\n");
    int connected = 0;
    for (int i = 0; i < 5; i++) {
        
        if (libusb_claim_interface(dev, 0) == LIBUSB_SUCCESS) {
            
            debug_log("succesfully claimed usb interface\n");
            connected = 1;
            
            [omgHack _notifyHandlersOfDevice:dev];
            
            return;
        }
        
        debug_log("libusb_claim_interface failed (attempt %d)\n", i);
    }
    
    if (connected == 0) {
        printf("failed to connect to the device\n");
        libusb_close(dev);
    }
}

@implementation SeekDeviceDiscovery

- (id)init {
    
    if ((self = [super init])) {
        
        self->discoveryHandlers = [[NSMutableArray alloc] init];
        self->device_discovery_queue = dispatch_queue_create("com.ea.device.finder", 0);
        self.isDiscovering = NO;
        
        
        if (libusb_init(&libusb_ctx) < 0) {
            debug_log("libusb_init context failed\n");
            return nil;
        }
        
        omgHack = self;
    }
    
    return self;
}


- (void)addDiscoveryHandler:(void (^)(SeekMosaicCamera *device))discoveryHandler {
    
    [self->discoveryHandlers addObject:discoveryHandler];
}

- (void)startDiscovery {
    
    if (self.isDiscovering) {
        return;
    }
    
    self.isDiscovering = YES;
    libusb_hotplug_register_callback(self->libusb_ctx, LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED, LIBUSB_HOTPLUG_ENUMERATE, S104SP_USB_VENDOR_ID, S104SP_USB_PRODUCT_ID, LIBUSB_HOTPLUG_MATCH_ANY, (libusb_hotplug_callback_fn)callback_function, NULL, NULL);

//    [self _beginDeviceDiscovery];
}

- (void)stopDiscovery {
    
    self.isDiscovering = NO;
}

- (void)_notifyHandlersOfDevice:(libusb_device_handle *)dev {
    
    // Notify handlers
    for (void (^discoveryHandler)(SeekMosaicCamera *device) in self->discoveryHandlers) {
        
        SeekMosaicCamera *camera = [[SeekMosaicCamera alloc] initWithHandle:dev delegate:nil];
        discoveryHandler(camera);
    }

    return;

    dispatch_async(device_discovery_queue, ^{
        
        while (self.isDiscovering) {
            
            libusb_device_handle *dev = NULL;
            while ((dev = libusb_open_device_with_vid_pid(self->libusb_ctx, S104SP_USB_VENDOR_ID, S104SP_USB_PRODUCT_ID)) == NULL) {
                debug_log("waiting for device...\n");
                sleep(1);
            }
            
            debug_log("found a new device\n");
            
            if (libusb_kernel_driver_active(dev, 0) && libusb_detach_kernel_driver(dev, 0) < 0) {
                debug_log("libusb_detach_kernel_driver failed\n");
                libusb_close(dev);
                continue;
            }
            
            if (libusb_set_configuration(dev, 1) < 0) {
                debug_log("libusb_set_configuration failed\n");
                libusb_close(dev);
                continue;
            }

            debug_log("attempting to connect to the device\n");
            int connected = 0;
            for (int i = 0; i < 5; i++) {
                
                if (libusb_claim_interface(dev, 0) == LIBUSB_SUCCESS) {
                    
                    debug_log("succesfully claimed usb interface\n");
                    connected = 1;
                    
                    // Notify handlers
                    for (void (^discoveryHandler)(SeekMosaicCamera *device) in self->discoveryHandlers) {
                        
                        SeekMosaicCamera *camera = [[SeekMosaicCamera alloc] initWithHandle:dev delegate:nil];
                        discoveryHandler(camera);
                    }
                    
                    break;
                }
                
                debug_log("libusb_claim_interface failed (attempt %d)\n", i);
            }
            
            if (connected == 0) {
                printf("failed to connect to the device\n");
                libusb_close(dev);
            }
/*
#if !(TARGET_OS_OSX)
            [self _killProcessesWithClaimsOnInterface];
#endif
*/
            sleep(1);
        }

        debug_log("device_discovery_queue terminated\n");
    });
}

@end
