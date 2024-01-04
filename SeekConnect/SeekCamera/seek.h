//
//  seek.h
//  SeekConnect
//
//  Created by Ethan Arbuckle
//

#ifndef seek_h
#define seek_h

#define DEBUG_LOGGING 1

#if DEBUG_LOGGING
#define debug_log(...) printf(__VA_ARGS__)
#else
#define debug_log(...)
#endif

#define SEEK_USB_VENDOR_ID 0x289d
#define SEEK_MOSAIC_USB_PRODUCT_ID 0x0011
#define SEEK_S104SP_USB_PRODUCT_ID 0x0010

//#define SEEK_MOSAIC_FRAME_HEIGHT 240
//#define SEEK_MOSAIC_FRAME_RAW_HEIGHT 260

//#define SEEK_MOSAIC_FRAME_WIDTH 320
//#define SEEK_MOSAIC_FRAME_RAW_WIDTH 342

#define S104SP_FRAME_WIDTH 208
#define S104SP_FRAME_HEIGHT 154

#define SEEK_FRAME_CURRENT_FRAME_COUNT_INDEX 1
#define SEEK_FRAME_TYPE_INDEX 2

#define SEEK_FRAME_TYPE_FSC_CALIBRATION 1
#define SEEK_FRAME_TYPE_IMAGE 3
#define SEEK_FRAME_TYPE_DP_CALIBRATION 4
#define SEEK_FRAME_TYPE_GRADIENT_CALIBRATION 6
#define SEEK_FRAME_TYPE_SHARPNESS_CALIBRATION 20


#define SET_FACTORY_SETTINGS_FEATURES 0x56
#define SET_FIRMWARE_INFO_FEATURES 0x55
#define SET_IMAGE_PROCESSING_MODE 0x3e
#define START_GET_IMAGE_TRANSFER 0x53
#define GET_FACTORY_SETTINGS 0x58
#define SET_OPERATION_MODE 0x3c
#define GET_OPERATION_MODE 61
#define GET_FIRMWARE_INFO 0x4e
#define SHUTTER_CONTROL 0x37
#define READ_CHIP_ID 0x36

#define LIBUSB_TRANSFER(handle, direction, bRequest, wLength, check, data) \
    do { \
        int ret = 0; \
        if ((ret = libusb_control_transfer(handle, direction, bRequest, 0, 0, data, wLength, 500)) check) { \
debug_log("libusb_control_transfer %s at line %d failure. err: %s\n", (direction == 0x41) ? "HOST->CAM" : "CAM->HOST", __LINE__, libusb_error_name(ret)); /*exit(-1);*/\
            return ret; \
        } \
    } while(0)

#define LIBUSB_TRANSFER_HOST_TO_CAM(handle, bRequest, wLength, check, ...) { uint8_t data[] = { __VA_ARGS__ }; LIBUSB_TRANSFER(handle, 0x41, bRequest, wLength, check, data); }
#define LIBUSB_TRANSFER_CAM_TO_HOST_GET_RESPONSE(handle, bRequest, wLength, check, data) LIBUSB_TRANSFER(handle, 0xc1, bRequest, wLength, check, data);
#define LIBUSB_TRANSFER_CAM_TO_HOST(handle, bRequest, wLength, check) { uint8_t data[wLength]; LIBUSB_TRANSFER_CAM_TO_HOST_GET_RESPONSE(handle, bRequest, wLength, check, data) }

#endif /* seek_h */
