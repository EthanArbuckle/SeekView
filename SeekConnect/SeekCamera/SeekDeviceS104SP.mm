//
//  SeekDeviceS104SP.m
//  SeekConnect
//
//  Created by Ethan Arbuckle on 12/17/23.
//

#import <opencv2/opencv.hpp>
#import "SeekDeviceS104SP.h"
#import "seek.h"

@implementation SeekDeviceS104SP

- (cv::Size)transferFrameSize {
    return cv::Size(208, 156);
}

- (cv::Size)displayFrameSize {
    return cv::Size(207, 154);
}

- (cv::Point)displayFrameOffset {
    return cv::Point(0, 0);
}

- (int)frameCounterFieldOffset {
    return 40;
}

- (int)frameTypeFieldOffset {
    return 10;
}

- (kern_return_t)_performDeviceInitialization {
    
    // Micro only? Wants a platform specified
    LIBUSB_TRANSFER_HOST_TO_CAM(self->usb_camera_handle, 84, 2, != 2, 0x00, 0x00);
    
    // Ensure operation mode is 0
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_OPERATION_MODE, 2, != 2, 0x00, 0x00);
    LIBUSB_TRANSFER_CAM_TO_HOST(usb_camera_handle, GET_OPERATION_MODE, 2, < 0);
    
    // Reset image processing settings
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_IMAGE_PROCESSING_MODE, 2, != 2, 0x08, 0x00);
    
    if (self.shutterMode == SeekCameraShutterModeManual) {
        LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SHUTTER_CONTROL, 4, != 4, 0xff, 0x00, 0xfd, 0x00);
    }
    else {
        LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SHUTTER_CONTROL, 4, != 4, 0xff, 0x00, 0xfc, 0x00);
    }
    
    // Init image processing
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_FACTORY_SETTINGS_FEATURES, 6, != 6, 0x08, 0x00, 0x02, 0x06, 0x00, 0x00);
    
    // Get device info
    uint8_t device_info[64];
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_FIRMWARE_INFO_FEATURES, 2, != 2, 0x17, 0x00);
    LIBUSB_TRANSFER_CAM_TO_HOST_GET_RESPONSE(usb_camera_handle, GET_FIRMWARE_INFO, 64, < 0, device_info);
    self.serialNumber = [NSString stringWithFormat:@"%s", (const char *)device_info];
    NSLog(@"connected to %@", self.serialNumber);
    
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_FIRMWARE_INFO_FEATURES, 2, != 2, 0x15, 0x00);
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_FACTORY_SETTINGS_FEATURES, 6, != 6, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00);
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_FIRMWARE_INFO_FEATURES, 2, != 2, 0x15, 0x00);
    
    LIBUSB_TRANSFER_CAM_TO_HOST(usb_camera_handle, GET_FIRMWARE_INFO, 64, < 0);
    LIBUSB_TRANSFER_CAM_TO_HOST(usb_camera_handle, GET_FACTORY_SETTINGS, 64, < 0);
    
    // Set operation mode to 1
    LIBUSB_TRANSFER_HOST_TO_CAM(usb_camera_handle, SET_OPERATION_MODE, 2, != 2, 0x01, 0x00);
    LIBUSB_TRANSFER_CAM_TO_HOST(usb_camera_handle, GET_OPERATION_MODE, 2, < 0);
    
    return KERN_SUCCESS;
}

- (kern_return_t)_requestFrameFromCamera {
    
    // Send the START_GET_IMAGE_TRANSFER command to the device
    LIBUSB_TRANSFER_HOST_TO_CAM(self->usb_camera_handle, START_GET_IMAGE_TRANSFER, 4, != 4, 0xc0, 0x7e, 0x00, 0x00);
    return KERN_SUCCESS;
}

@end
