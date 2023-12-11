//
//  SeekMosaicCamera.mm
//  SeekMosaicViewer
//
//  Created by Ethan Arbuckle
//

#import <opencv2/opencv.hpp>
#import <libusb.h>
#import "SeekMosaicCamera.h"
#import "seek.h"

#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
extern "C" {
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
}
#endif


@interface SeekMosaicCamera () {
    
    dispatch_queue_t frame_fetch_queue;
    dispatch_queue_t frame_render_queue;
    dispatch_queue_t frame_processing_queue;
    dispatch_queue_t device_discovery_queue;
    
    libusb_device_handle *usb_camera_handle;
    libusb_context *libusb_ctx;
    
    uint16_t *image_tx_buf;
    cv::Mat image_tx_mat;
    uint16_t *image_tx_out_buff;
    cv::Mat image_tx_out_mat;
    
    cv::Mat smoothing_accumulator;
    cv::Mat edge_accumulator;
    
    cv::Mat intermediary_frame;
    
    cv::Mat fsc_calibration_frame;
    cv::Mat gradient_correction_frame;
    cv::Mat sharpness_correction_frame;
    cv::Mat dead_pixel_mask;
    std::vector<cv::Point> dead_pixels;
    
    RGB_ColorMap tyrian_color_map[256];
    RGB_ColorMap tyrian_rendered_frame[(S104SP_FRAME_WIDTH * 3) * (S104SP_FRAME_HEIGHT * 3)];
    
    float exposure_multiplier;
    
    uint16_t camera_reported_frame_count;
    
    NSLock *fbLock;
    
    int tx_error_count;
    
#if TARGET_OS_OSX
    NSBitmapImageRep *renderedBitmap;
    NSImage *renderedImageOutput;
#endif
}

@end


@implementation SeekMosaicCamera

- (id)initWithDelegate:(id<SeekCameraDelegate>)delegate {
    
    if ((self = [super init])) {
        
        self.delegate = delegate;
        self.shutterMode = SeekCameraShutterModeManual;//SeekCameraShutterModeAuto;
        
        self.lockExposure = 1;
        self.exposureMinThreshold = -1;
        self.exposureMaxThreshold = -1;
        
        self.edgeDetection = YES;
        self.edgeDetectioneMinThreshold = 90;
        self.edgeDetectionMaxThreshold = 110;
        
        self.scaleFactor = 3;
        self.blurFactor = 1.0;
        self.sharpenFactor = 0; //5
        self.opencvColormap = -1;
        
        // Usb setup
        usb_camera_handle = NULL;
        libusb_ctx = NULL;
        
        fbLock = [[NSLock alloc] init];
        
        // Queues for fetching frames, processing them, and drawing them
        dispatch_queue_attr_t attrs = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        frame_fetch_queue = dispatch_queue_create("com.ea.frame.fetcher", attrs);
        frame_render_queue = dispatch_queue_create("com.ea.frame.render", attrs);
        frame_processing_queue = dispatch_queue_create("com.ea.frame.render", attrs);
        device_discovery_queue = dispatch_queue_create("com.ea.device.finder", 0);
        
        image_tx_buf = (uint16_t *)malloc(65535);
        if (image_tx_buf == NULL) {
            [[NSException exceptionWithName:@"memory" reason:@"memory" userInfo:nil] raise];
        }
        bzero(self->image_tx_buf, 65535);
        
        image_tx_mat = cv::Mat(S104SP_FRAME_HEIGHT + 2, S104SP_FRAME_WIDTH + 1,  CV_16UC1, (void *)self->image_tx_buf, cv::Mat::AUTO_STEP);
        image_tx_mat = image_tx_mat(cv::Rect(0, 1, S104SP_FRAME_WIDTH, S104SP_FRAME_HEIGHT));
        
        image_tx_out_buff = (uint16_t *)malloc(65535);
        if (image_tx_out_buff == NULL) {
            [[NSException exceptionWithName:@"memory" reason:@"memory" userInfo:nil] raise];
        }
        bzero(self->image_tx_out_buff, 65535);
        
        if (libusb_init(&libusb_ctx) < 0) {
            debug_log("libusb_init context failed\n");
            return nil;
        }
        
        build_tyrian_like_color_map(tyrian_color_map);
    }
    
    return self;
}

- (void)_beginDeviceDiscovery {
    
    dispatch_async(device_discovery_queue, ^{
        
        while ((self->usb_camera_handle = libusb_open_device_with_vid_pid(self->libusb_ctx, S104SP_USB_VENDOR_ID, S104SP_USB_PRODUCT_ID)) == NULL) {
            debug_log("waiting for device...\n");
            sleep(1);
        }
        
        debug_log("found a new device: %p\n", self->usb_camera_handle);
        
        if (libusb_kernel_driver_active(self->usb_camera_handle, 0) && libusb_detach_kernel_driver(self->usb_camera_handle, 0) < 0) {
            debug_log("libusb_detach_kernel_driver failed\n");
            libusb_close(self->usb_camera_handle);
            libusb_exit(self->libusb_ctx);
            return;
        }
        
        if (libusb_set_configuration(self->usb_camera_handle, 1) < 0) {
            debug_log("libusb_set_configuration failed\n");
            libusb_close(self->usb_camera_handle);
            libusb_exit(self->libusb_ctx);
            return;
        }
        
        debug_log("attempting to connect to the device\n");
        for (int i = 0; i < 5; i++) {
            
            if (libusb_claim_interface(self->usb_camera_handle, 0) == LIBUSB_SUCCESS) {
                
                debug_log("succesfully claimed usb interface\n");
                [self _handleDeviceConnected];
                return;
            }
            
            debug_log("libusb_claim_interface failed\n");
            
            
#if !(TARGET_OS_OSX)
            [self _killProcessesWithClaimsOnInterface];
#endif
            sleep(1);
        }
        
        // Failed to connect
        printf("Failed to connect to device. Restarting libusb and discovery queue\n");
        libusb_close(self->usb_camera_handle);
        libusb_exit(self->libusb_ctx);
        
        if (libusb_init(&self->libusb_ctx) < 0) {
            debug_log("libusb_init context failed\n");
            return;
        }
        
        [self start];
        
        debug_log("device_discovery_queue terminated\n");
    });
}

- (void)_handleDeviceDisconnected {
    
    if ([self.delegate respondsToSelector:@selector(seekCameraDidDisconnect:)]) {
        [self.delegate seekCameraDidDisconnect:self];
    }
    
    self->usb_camera_handle = NULL;
    
    // Startup the device discovery queue. For some reason there needs to be a delay, otherwise
    // libusb "succeeds" in reconnecting but then fails when taking ownership
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self _beginDeviceDiscovery];
    });
    
}

- (kern_return_t)_handleDeviceConnected {
    
    [self _performDeviceInitialization];
    
    // Notify delegate of connection event
    if ([self.delegate respondsToSelector:@selector(seekCameraDidConnect:)]) {
        [self.delegate seekCameraDidConnect:self];
    }
    
    // Begin up frame capturing
    [self _beginFrameTransferQueue];
    
    return KERN_SUCCESS;
}

- (kern_return_t)_performDeviceInitialization {
    
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

- (void)_beginFrameTransferQueue {
    
    dispatch_async(self->frame_fetch_queue, ^{
        
        while (self->usb_camera_handle != NULL) {
            
            if ([self _transferFrameFromCamera] == LIBUSB_ERROR_NO_DEVICE) {
                // Connection lost
                [self _handleDeviceDisconnected];
                break;
            }
            else if ([self _transferFrameFromCamera] != KERN_SUCCESS && self->tx_error_count >= 5) {
                
                debug_log("something seems wrong. attempting to reinitialize the session\n");
                [self _performDeviceInitialization];
                continue;
                
                libusb_release_interface(self->usb_camera_handle, 0);
                libusb_close(self->usb_camera_handle);
                libusb_exit(self->libusb_ctx);
                
                self->usb_camera_handle = NULL;
                sleep(1);
                
#if !(TARGET_OS_OSX)
                [self _killProcessesWithClaimsOnInterface];
#endif
                if (libusb_init(&self->libusb_ctx) < 0) {
                    debug_log("libusb_init context failed\n");
                    return;
                }
                
                [self start];
                break;
            }
        }
        
        debug_log("frame_fetch_queue terminated\n");
    });
}

- (kern_return_t)_transferFrameFromCamera {
    
    // Ask the device for an image, copy it into image_tx_buf
    LIBUSB_TRANSFER_HOST_TO_CAM(self->usb_camera_handle, START_GET_IMAGE_TRANSFER, 4, != 4, 0xc0, 0x7e, 0x00, 0x00);
    
    uint8_t *buf = (uint8_t *)self->image_tx_out_buff;
    
    int total_bytes_read = 0;
    int expected_transaction_len = 64896;
    while (total_bytes_read < expected_transaction_len) {
        
        int bytes_transferred;
        int transfer_status = 0;
        
        if ((transfer_status = libusb_bulk_transfer(self->usb_camera_handle, 0x81, &buf[total_bytes_read], 4096, &bytes_transferred, 250)) != KERN_SUCCESS) {
            debug_log("libusb_bulk_transfer failed after %d bytes out of %d: %s\n", total_bytes_read, expected_transaction_len, libusb_strerror(transfer_status));
            [self->fbLock unlock];
            
            self->tx_error_count += 1;
            return KERN_FAILURE;
        }
        
        total_bytes_read += bytes_transferred;
    }
    
    // Reset transfer error counter
    self->tx_error_count = 0;
    
    [self->fbLock lock];
    memcpy(self->image_tx_buf, buf, total_bytes_read);
    [self->fbLock unlock];
    
    dispatch_async(self->frame_processing_queue, ^{
        [self _processIngestedFrameWithLength:total_bytes_read];
    });
    
    return KERN_SUCCESS;
}

- (void)_processIngestedFrameWithLength:(int)length {
    
    self->camera_reported_frame_count = self->image_tx_buf[S104SP_FRAME_CURRENT_FRAME_COUNT_INDEX];
    
    switch (self->image_tx_buf[S104SP_FRAME_TYPE_INDEX]) {
            
            
        case SEEK_FRAME_TYPE_GRADIENT_CALIBRATION: {

            debug_log("received gradient correction frame\n");
            self->image_tx_mat.copyTo(self->gradient_correction_frame);
            self->gradient_correction_frame = 0x4000 + self->gradient_correction_frame;

            break;
        }

        case SEEK_FRAME_TYPE_SHARPNESS_CALIBRATION: {

            debug_log("received sharpness correction frame\n");

            double f_min;
            cv::minMaxLoc(self->image_tx_mat, NULL, &f_min);

            self->image_tx_mat.copyTo(self->sharpness_correction_frame);

            if (f_min == 0) {
                self->sharpness_correction_frame = 0x4000 - self->sharpness_correction_frame;
            }
            else {
                cv::normalize(self->sharpness_correction_frame, self->sharpness_correction_frame, 0, 2048, cv::NORM_MINMAX);
            }
            
            self->sharpness_correction_frame = 0x2000 - self->sharpness_correction_frame;

            break;
        }

        case SEEK_FRAME_TYPE_FSC_CALIBRATION: {
            
            // Flat scene correction calibration frame
            debug_log("received flat scene correction frame\n");
            self->image_tx_mat.copyTo(self->fsc_calibration_frame);
            self->fsc_calibration_frame = 0x4000 - self->fsc_calibration_frame;

            break;
        }
            
        case SEEK_FRAME_TYPE_DP_CALIBRATION: {
            
            debug_log("received dead pixel calibration frame\n");
            
            // Dead pixel calibration frame
            [self _buildDeadPixelMask];
            
            // This is expected to be the first frame.
            // After receiving it, and the shutter mode is set to manual,
            // trigger the shutter once so that an initial correction is applied
            if (self.shutterMode == SeekCameraShutterModeManual) {
                [self toggleShutter];
            }
            
            break;
        }
    
        case SEEK_FRAME_TYPE_IMAGE: {
            // Image frame
            self.frameCount += 1;
            
            // The dead pixel correction frame is sent before image frames, but
            // it's possible for it to have been missed if the device wasn't deinititialized
            // after the previous session.
            // If no dead pixel frame has been received, run through the initialization sequence again
            if (self->dead_pixel_mask.empty()) {
                [self _performDeviceInitialization];
                return;
            }
            
            if (self.shutterMode == SeekCameraShutterModeManual) {
                if (self->camera_reported_frame_count <= 60 && (self->camera_reported_frame_count % 20) == 0) {
                 //   [self toggleShutter];
                }
            }
            
            // Process image frame
            [self _processIngestedImageFrame];
            
            break;
        }
            
        default: {
            // Unhandled frame type
            debug_log("received unknown frame type: %d\n", self->image_tx_buf[S104SP_FRAME_TYPE_INDEX]);
            break;
        }
    }
}

cv::Mat findPerimeter(const cv::Mat& binaryImage) {
    
    cv::Mat bwImage = binaryImage.clone();
    
    cv::Mat perimeter = cv::Mat::zeros(bwImage.size(), CV_8UC1);
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(10, 10));
    
    cv::Mat dilated;
    cv::dilate(bwImage, dilated, kernel);
    
    cv::Mat eroded;
    cv::erode(bwImage, eroded, kernel);
    
    cv::subtract(dilated, eroded, perimeter);
    return perimeter;
}

- (void)_processIngestedImageFrame {
    
//    [self->fbLock lock];
    
    if (!self->fsc_calibration_frame.empty()) {
        self->image_tx_mat += self->fsc_calibration_frame;
    }

    /*
    if (!self->sharpness_correction_frame.empty()) {
        self->image_tx_mat += self->sharpness_correction_frame;
    }
    */

    /*
    if (!self->gradient_correction_frame.empty()) {
        debug_log("applying gradient correction\n");
        self->image_tx_mat += self->gradient_correction_frame;
    }
    */
    
    intermediary_frame.setTo(65535);

    if (self->dead_pixel_mask.empty()) {
        debug_log("processing image while without dead pixel correction\n");
        self->image_tx_mat.copyTo(intermediary_frame);
    }
    else {
        // Apply dead pixel mask
        self->image_tx_mat.copyTo(intermediary_frame, dead_pixel_mask);
        for (int i = 0; i < self->dead_pixels.size(); i++) {
            cv::Point pixel = self->dead_pixels[i];
            intermediary_frame.at<uint16_t>(pixel) = [self _getAdjacentPixelMeanAtPoint:pixel fromImage:intermediary_frame deadPixelMarker:0xffff];
        }
    }


    
//    [self->fbLock unlock];
    
    // Normalize to make use of full colorspace
    if (self.lockExposure) {
        
        if (self.exposureMinThreshold == -1) {
            cv::minMaxLoc(intermediary_frame, &_exposureMinThreshold, &_exposureMaxThreshold);
            self->exposure_multiplier = 65535 / (self.exposureMaxThreshold - self.exposureMinThreshold);
        }
        
        for (int y = 0; y < intermediary_frame.rows; y++) {
            
            for (int x = 0; x < intermediary_frame.cols; x++) {
                uint16_t val = intermediary_frame.at<uint16_t>(y, x);
                if (val > self.exposureMaxThreshold) {
                    val = 65535;
                } else if (val < self.exposureMinThreshold) {
                    val = 0;
                } else {
                    val = (val - self.exposureMinThreshold) * self->exposure_multiplier;
                }
                intermediary_frame.at<uint16_t>(y, x) = val;
            }
        }
        
        // The first frame min value may be 0. If so, reset it so that
        // min/max is recalculated on the next frame
        if (self.exposureMinThreshold == 0) {
            self.exposureMinThreshold = -1;
        }
    }
    else {
        cv::normalize(intermediary_frame, intermediary_frame, 0, 65535, cv::NORM_MINMAX);
    }
    
    // Convert to 1 channel grayscale
    cv::Mat frame_one_channel;
    intermediary_frame.convertTo(frame_one_channel, CV_8UC1, 1.0 / 256.0);
    
    [self _applyTemporalSmoothingToFrame:frame_one_channel usingAccumulator:self->smoothing_accumulator alpha:0.90];
    
    cv::Mat frame_three_channel;
    
    // Blur
    int corrected_blur_factor = self.blurFactor;
    if (corrected_blur_factor > 0) {
        if ((corrected_blur_factor % 2) == 0) {
            corrected_blur_factor += 1;
        }
        
        cv::GaussianBlur(frame_one_channel, frame_three_channel, cv::Size(corrected_blur_factor, corrected_blur_factor), 0);
    }
    else {
        frame_one_channel.copyTo(frame_three_channel);
    }
    
//    int x = 40;
//   int y = 1;
//   int width = 160;
//   int height = 153;
//
//   cv::Point top_left(x, y);
//   cv::Point bottom_right(x + width, y + height);
//
//   // Define the color of the rectangle (B, G, R) - red in this case
//   cv::Scalar rectangle_color(0, 0, 255); // Red color
//
//   // Define the thickness of the border.
//   // If you set it to CV_FILLED, the rectangle will be filled.
//   int thickness = 2; // Change this for a thicker or thinner border
//
//   // Draw the rectangle on the image
//   cv::rectangle(frame_three_channel, top_left, bottom_right, rectangle_color, thickness);

    
    // Adjust size
    cv::resize(frame_three_channel, frame_three_channel, cv::Size(), self.scaleFactor, self.scaleFactor, cv::INTER_LINEAR);

    // Edge detection
    if (self.edgeDetection) {
        
        cv::Mat edge_detect_blur_one_channel;
        intermediary_frame.convertTo(edge_detect_blur_one_channel, CV_8UC1, 1.0 / 256.0);
        
        cv::resize(edge_detect_blur_one_channel, edge_detect_blur_one_channel, cv::Size(), self.scaleFactor, self.scaleFactor, cv::INTER_LINEAR);
        cv::GaussianBlur(edge_detect_blur_one_channel, edge_detect_blur_one_channel, cv::Size(1, 1), 0);
        
        cv::Mat edges = findPerimeter(edge_detect_blur_one_channel);
        cv::Mat edgeOverlay = cv::Mat::zeros(edges.size(), edges.type());
        edges.copyTo(edgeOverlay, edges);
        
        [self _applyTemporalSmoothingToFrame:edgeOverlay usingAccumulator:self->edge_accumulator alpha:0.9];
        
        cv::addWeighted(frame_three_channel, 1, edgeOverlay, 1, 0, frame_three_channel);
    }
    
    // Accumulate some processed frames before handing a final rendered image to the delegate
    if (self.frameCount < 5) {
        debug_log("still accumulating frames... frame count: %d\n", self.frameCount);
        return;
    }
    
    // Sharpen
    if (self.sharpenFactor > 0) {
        cv::Mat kernel = (cv::Mat_<float>(3, 3) << 0, -1, 0, -1, self.sharpenFactor, -1, 0, -1, 0);
        cv::filter2D(frame_three_channel, frame_three_channel, -1, kernel);
    }
    
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
    cv::morphologyEx(frame_three_channel, frame_three_channel, cv::MORPH_ERODE, kernel);

    // Apply color map
    if (self.opencvColormap >= 0) {
        
        // User specified an opencv colormap
        cv::applyColorMap(frame_three_channel, frame_three_channel, self.opencvColormap);
        
        [self.delegate seekCamera:self sentFrame:[self _imageFromPixelData:frame_three_channel.data width:frame_three_channel.cols height:frame_three_channel.rows]];
    }
    else {
        // No colormap specified, use one that is similar to Seek's Tyrian colormmap
        for (int i = 0; i < frame_three_channel.rows * frame_three_channel.cols; i++) {
            uint8_t pixelValue = frame_three_channel.data[i];
            tyrian_rendered_frame[i] = tyrian_color_map[pixelValue];
        }
        
        [self.delegate seekCamera:self sentFrame:[self _imageFromPixelData:(unsigned char *)tyrian_rendered_frame width:frame_three_channel.cols height:frame_three_channel.rows]];
    }
}

- (id)_imageFromPixelData:(unsigned char *)source width:(int)width height:(int)height {
#if TARGET_OS_OSX
    return [self _nsimageFromPixelData:source width:width height:height];
#else
    return [self _uiimageFromPixelData:source width:width height:height];
#endif
}

#if TARGET_OS_OSX
- (NSImage *)_nsimageFromPixelData:(unsigned char *)source width:(int)width height:(int)height {
    
    [self->fbLock lock];
    
    if (!self->renderedBitmap || self->renderedBitmap.size.width != width) {
        self->renderedBitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:3 hasAlpha:0 isPlanar:0 colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:0 bytesPerRow:width * 3 bitsPerPixel:24];
        
        self->renderedImageOutput =  [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
        [self->renderedImageOutput addRepresentation:self->renderedBitmap];
    }
    
    memcpy([self->renderedBitmap bitmapData], source, width * height * 3);
    NSImage *outputImage = [self->renderedImageOutput copy];
    [self->fbLock unlock];
    
    return outputImage;
}
#else
- (UIImage *)_uiimageFromPixelData:(unsigned char *)source width:(int)width height:(int)height {
    
    [self->fbLock lock];
    
    NSData *data = [NSData dataWithBytes:source length:width * height * 3];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(960, 720, 8, 24, width * 3, colorSpace, kCGImageAlphaNone, provider, NULL, false, kCGRenderingIntentDefault);
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    [self->fbLock unlock];
    
    return finalImage;
}
#endif

- (void)_buildDeadPixelMask {
    
    self->dead_pixel_mask = cv::Mat();
    cv::Mat converted_frame;
    self->image_tx_mat.convertTo(converted_frame, CV_32FC1);
    
    double frame_max_val;
    cv::minMaxLoc(converted_frame, NULL, &frame_max_val, NULL, NULL);
    
    int channels[] = {0};
    int histogram_bins[] = {0x4000};
    float value_range[] = {0, 0x4000};
    const float *ranges[] = { value_range };
    
    cv::Mat histogram;
    cv::calcHist(&converted_frame, 1, channels, cv::Mat(), histogram, 1, histogram_bins, ranges, true, false);
    histogram.at<float>(0, 0) = 0;
    
    cv::Point histogram_peak;
    cv::minMaxLoc(histogram, NULL, NULL, NULL, &histogram_peak);
    double threshold_val = histogram_peak.y - (frame_max_val - histogram_peak.y);
    
    cv::threshold(converted_frame, converted_frame, threshold_val, 255, cv::THRESH_BINARY);
    converted_frame.convertTo(self->dead_pixel_mask, CV_8UC1);
    
    self->dead_pixel_mask.convertTo(converted_frame, CV_16UC1);
    self->dead_pixels.clear();
    
    int remaining_pixels = 1;
    while (remaining_pixels) {
        
        remaining_pixels = 0;
        for (int row = 0; row < converted_frame.rows; row++) {
            for (int col = 0; col < converted_frame.cols; col++) {
                cv::Point point = {col, row};
                
                if (converted_frame.at<uint16_t>(row, col) != 0) {
                    continue;
                }
                
                if ([self _getAdjacentPixelMeanAtPoint:point fromImage:converted_frame deadPixelMarker:0] != 0) {
                    self->dead_pixels.push_back(point);
                    converted_frame.at<uint16_t>(row, col) = 255;
                } else {
                    remaining_pixels = 1;
                }
            }
        }
    }
}

- (uint16_t)_getAdjacentPixelMeanAtPoint:(cv::Point)point fromImage:(cv::Mat&)source deadPixelMarker:(uint32_t)marker {
    
    uint32_t value = 0;
    uint32_t div = 0;
    int dx[] = {-1, 1, 0, 0};
    int dy[] = {0, 0, -1, 1};
    
    uint16_t *data = (uint16_t *)source.data;
    for (int i = 0; i < 4; i++) {
        
        int nx = point.x + dx[i];
        int ny = point.y + dy[i];
        
        if (nx >= 0 && nx < source.cols && ny >= 0 && ny < source.rows) {
            
            uint16_t neighbor = data[ny * source.cols + nx];
            if (neighbor != marker) {
                value += neighbor;
                div++;
            }
        }
    }
    
    return div ? value / div : 0;
}

- (void)_applyTemporalSmoothingToFrame:(const cv::Mat&)frame usingAccumulator:(cv::Mat&)accumulator alpha:(double)alpha {
    
    if (accumulator.empty()) {
        frame.convertTo(accumulator, CV_32F);
    }
    
    cv::accumulateWeighted(frame, accumulator, alpha);
    accumulator.convertTo(frame, frame.type());
}

- (void)start {
    
    if (!self.delegate) {
        return;
    }
    
    self.frameCount = 0;
    self->tx_error_count = 0;
    [self _beginDeviceDiscovery];
}

- (void)toggleShutter {
    
    if (self->usb_camera_handle == NULL) {
        return;
    }
    
    // Immediately toggle shutter
    kern_return_t (^toggleShutter)(void) = ^kern_return_t(void) {
        LIBUSB_TRANSFER_HOST_TO_CAM(self->usb_camera_handle, SHUTTER_CONTROL, 4, != 4, 0xff, 0x00, 0xf9, 0x00);
        return KERN_SUCCESS;
    };
    
    toggleShutter();
}

- (void)setOpencvColormap:(int)opencvColormap {
    
    if (opencvColormap > cv::COLORMAP_DEEPGREEN || opencvColormap < 0) {
        _opencvColormap = -1;
    }
    else {
        _opencvColormap = opencvColormap;
    }
}

- (void)resetExposureThresholds {
    self.exposureMinThreshold = -1;
    self.exposureMaxThreshold = -1;
}

- (void)setExposureMaxThreshold:(double)exposureMaxThreshold {
    _exposureMaxThreshold = exposureMaxThreshold;
    self->exposure_multiplier = 65535 / (self.exposureMaxThreshold - self.exposureMinThreshold);
}

- (void)setExposureMinThreshold:(double)exposureMinThreshold {
    _exposureMinThreshold = exposureMinThreshold;
    self->exposure_multiplier = 65535 / (self.exposureMaxThreshold - self.exposureMinThreshold);
}

#if !(TARGET_OS_OSX)

- (void)_killProcessesWithClaimsOnInterface {
    // launchctl unload /System/Library/LaunchDaemons/com.apple.usb.networking.addNetworkInterface.plist
    
    // Terminate accessoryd
    int accessoryd_pid = [self _getPIDForProcess:@"accessoryd"];
    if (accessoryd_pid > 0) {
        debug_log("terminating accessoryd (%d)\n", accessoryd_pid);
        if (kill(accessoryd_pid, SIGTERM) != KERN_SUCCESS) {
            debug_log("failed to terminate accessoryd (%d)\n", accessoryd_pid);
        }
        else {
            debug_log("succesfully terminated accessoryd (%d)\n", accessoryd_pid);
        }
    }
    else {
        debug_log("failed to get pid for accessoryd. possibly not running?\n");
    }
}

- (int)_getPIDForProcess:(NSString *)processName {
    
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    uint miblen = 4;
    
    size_t size;
    if (sysctl(mib, miblen, NULL, &size, NULL, 0) == -1) {
        return -1;
    }
    
    struct kinfo_proc *process = (struct kinfo_proc *)malloc(size);
    if (sysctl(mib, miblen, process, &size, NULL, 0) == -1) {
        free(process);
        return -1;
    }
    
    for (int i = 0; i < size / sizeof(struct kinfo_proc); i++) {
        if (&process[i] != NULL && strncmp(process[i].kp_proc.p_comm, processName.UTF8String, MAXCOMLEN) == 0) {
            pid_t pid = process[i].kp_proc.p_pid;
            free(process);
            return pid;
        }
    }
    
    free(process);
    return -1;
}

#endif

@end
