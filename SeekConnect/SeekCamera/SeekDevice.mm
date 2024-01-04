//
//  SeekDevice.mm
//  SeekConnect
//
//  Created by Ethan Arbuckle
//

#import <opencv2/opencv.hpp>
#import "SeekDevice.h"
#import "seek.h"

#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
extern "C" {
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
}
#endif

#import "tyrian_color_map.h"

@interface SeekDevice () {
    
    dispatch_queue_t frame_fetch_queue;
    dispatch_queue_t frame_processing_queue;
    
    uint16_t *raw_transfer_frame_buf;
    cv::Mat raw_transfer_frame;
    pthread_mutex_t raw_transfer_frame_mutex;
    
    cv::Mat smoothing_accumulator;
    cv::Mat edge_accumulator;
    
    cv::Mat fsc_calibration_frame;
    cv::Mat gradient_correction_frame;
    cv::Mat sharpness_correction_frame;
    cv::Mat dead_pixel_mask;
    std::vector<cv::Point> dead_pixels;
    
    float exposure_multiplier;
    
    uint16_t camera_reported_frame_count;
    
    int tx_error_count;
    
#if TARGET_OS_OSX
    NSBitmapImageRep *renderedBitmap;
    NSImage *renderedImageOutput;
#endif
}

// Device-specific values
@property (nonatomic) cv::Size transferFrameSize;
@property (nonatomic) cv::Size displayFrameSize;
@property (nonatomic) cv::Point displayFrameOffset;

@property (nonatomic) int frameCounterFieldOffset;
@property (nonatomic) int frameTypeFieldOffset;

@end


@implementation SeekDevice

- (id)initWithDeviceHandle:(libusb_device_handle *)device_handle delegate:(id<SeekDeviceDelegate>)delegate {
    
    if ((self = [super init])) {
        
        if (device_handle == NULL) {
            debug_log("SeekDevice initWithDeviceHandle requires a non-null device handle\n");
            return nil;
        }

        self->usb_camera_handle = device_handle;
        self.delegate = delegate;
        self.shutterMode = SeekCameraShutterModeAuto;
        
        self.lockExposure = NO;
        self.exposureMinThreshold = -1;
        self.exposureMaxThreshold = -1;
        
        self.edgeDetection = NO;
        self.edgeDetectioneMinThreshold = 90;
        self.edgeDetectionMaxThreshold = 110;
        self.performLastPassErosion = YES;
        
        self.edgeDetectionPerimeterSize = 4;
        self.scaleFactor = 3;
        self.blurFactor = 0;
        self.sharpenFactor = 0; //5
        self.opencvColormap = -1;
        
        if ([self _attachToDeviceHandle:device_handle] != KERN_SUCCESS) {
            debug_log("failed to attach to usb device! connection failed\n");
            return nil;
        }
        
        // Queues for fetching frames, processing them, and drawing them
        dispatch_queue_attr_t attrs = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        frame_fetch_queue = dispatch_queue_create("com.ea.frame.fetcher", attrs);
        frame_processing_queue = dispatch_queue_create("com.ea.frame.render", attrs);
        
        uint32_t transfer_frame_width = self.transferFrameSize.width;
        uint32_t transfer_frame_height = self.transferFrameSize.height;
        debug_log("transfer frame size: %d x %d\n", transfer_frame_width, transfer_frame_height);
        
        pthread_mutex_init(&self->raw_transfer_frame_mutex, NULL);
        pthread_mutex_lock(&self->raw_transfer_frame_mutex);
        
        self->raw_transfer_frame_buf = (uint16_t *)calloc(transfer_frame_width * transfer_frame_height, 2);
        if (self->raw_transfer_frame_buf == NULL) {
            NSLog(@"failed to alloc %d bytes", transfer_frame_width * transfer_frame_height);
            return nil;
        }
        
        uint32_t display_frame_width = self.displayFrameSize.width;
        uint32_t display_frame_height = self.displayFrameSize.height;
        debug_log("display frame size: %d x %d\n", display_frame_width, display_frame_height);
        
        cv::Rect display_roi = cv::Rect(self.displayFrameOffset.x, self.displayFrameOffset.y, display_frame_width, display_frame_height);
        debug_log("display_roi = (%d, %d, %d, %d). max-width: %d, max height: %d\n", display_roi.x, display_roi.y, display_roi.width, display_roi.height, display_roi.x + display_roi.width, display_roi.y + display_roi.height);
        
        if (display_roi.x + display_roi.width > transfer_frame_width) {
            NSLog(@"display_roi.x + width exceeds image_tx_mat width by: %d", transfer_frame_width - (display_roi.x + display_roi.width));
            return nil;
        }
        
        if (display_roi.y + display_roi.height > transfer_frame_height) {
            NSLog(@"display_roi.y + height exceeds image_tx_mat height by: %d",  transfer_frame_height - (display_roi.y + display_roi.height));
            return nil;
        }
        
        self->raw_transfer_frame = cv::Mat(transfer_frame_height, transfer_frame_width, CV_16UC1, (void *)self->raw_transfer_frame_buf, cv::Mat::AUTO_STEP);
        self->raw_transfer_frame = self->raw_transfer_frame(display_roi);
        
        pthread_mutex_unlock(&self->raw_transfer_frame_mutex);
    }
    
    return self;
}

- (kern_return_t)_performDeviceInitialization {
    NSLog(@"_performDeviceInitialization must be called from a device-specific subclass");
    return KERN_FAILURE;
}

- (kern_return_t)_requestFrameFromCamera {
    NSLog(@"_requestFrameFromCamera must be called from a device-specific subclass");
    return KERN_FAILURE;
}

- (kern_return_t)_attachToDeviceHandle:(libusb_device_handle *)device_handle {
    
    if (libusb_kernel_driver_active(device_handle, 0) != LIBUSB_SUCCESS && libusb_detach_kernel_driver(device_handle, 0) != LIBUSB_SUCCESS) {
        debug_log("libusb_detach_kernel_driver failed\n");
        libusb_close(device_handle);
        return KERN_FAILURE;
    }
    
    if (libusb_set_configuration(device_handle, 1) != LIBUSB_SUCCESS) {
        debug_log("libusb_set_configuration failed\n");
        libusb_close(device_handle);
        return KERN_FAILURE;
    }

    debug_log("attempting to connect to the device\n");
    for (int i = 0; i < 5; i++) {
        
        if (libusb_claim_interface(device_handle, 0) == LIBUSB_SUCCESS) {
            
            debug_log("succesfully claimed usb interface\n");
            return KERN_SUCCESS;
        }
        
        debug_log("libusb_claim_interface failed (attempt %d)\n", i);
    }
    
    printf("failed to connect to the device\n");
    libusb_close(device_handle);

    return KERN_FAILURE;
}


- (void)_handleDeviceDisconnected {
    
    self->usb_camera_handle = NULL;
    
    if ([self.delegate respondsToSelector:@selector(seekCameraDidDisconnect:)]) {
        [self.delegate seekCameraDidDisconnect:self];
    }
}

- (void)start {
    
    if (self->usb_camera_handle == NULL) {
        printf("Attempting to start capturing but device handle is null\n");
        return;
    }
    
    [self _handleDeviceConnected];
}

- (void)_handleDeviceConnected {

    // Initialize device and begin capturing frames
    [self _initializeConnection];
    
    // Notify delegate of connection event
    if ([self.delegate respondsToSelector:@selector(seekCameraDidConnect:)]) {
        [self.delegate seekCameraDidConnect:self];
    }
}

- (void)_initializeConnection {
    
    self.frameCount = 0;
    self->tx_error_count = 0;
    self->camera_reported_frame_count = 0;

    [self _performDeviceInitialization];
    
    [self _beginFrameTransferQueue];
}

- (void)_reinitializeConnection {
//    
//    if (self->usb_camera_handle == NULL) {
//        debug_log("cannot reinitialize a non-existent connection\n");
//        [self _handleDeviceDisconnected];
//        return;
//    }
//        
//    libusb_device *usb_device = libusb_get_device(self->usb_camera_handle);
//    if (usb_device == NULL) {
//        debug_log("failed to get libusb_device for camera handle\n");
//        [self _handleDeviceDisconnected];
//        return;
//    }
//
//    debug_log("releasing interface and closing device handle\n");
////    libusb_release_interface(self->usb_camera_handle, 0);
//    /*libusb_close*/(self->usb_camera_handle);
////    self->usb_camera_handle = NULL;
//    
//    if (libusb_open(usb_device, &self->usb_camera_handle) != LIBUSB_SUCCESS) {
//        debug_log("libusb_open failed during reinitialization\n");
//        [self _handleDeviceDisconnected];
//        return;
//    }
//    
//    if ([self _attachToDeviceHandle:self->usb_camera_handle] != KERN_SUCCESS) {
//        debug_log("failed to complete reinitialization of device\n");
//        [self _handleDeviceDisconnected];
//        return;
//    }
    
    [self _initializeConnection];
}

- (void)_beginFrameTransferQueue {
    
    dispatch_async(self->frame_fetch_queue, ^{
        
        while (self->usb_camera_handle != NULL) {
            
            switch ([self _transferFrameFromCamera]) {
                
                case LIBUSB_SUCCESS: {
                    
                    // Reset transfer error counter
                    if (self->tx_error_count > 0) {
                        self->tx_error_count = 0;
                    }

                    break;
                }

                case LIBUSB_ERROR_NO_DEVICE: {
                    
                    debug_log("Lost connection to device\n");
                    [self _handleDeviceDisconnected];
                    return;
                }
                
                // Some type of error
                default: {
                    
                    if (++self->tx_error_count >= 10) {
                        
                        debug_log("something seems wrong. attempting to reinitialize the session\n");
                        
#if !(TARGET_OS_OSX)
                [self _killProcessesWithClaimsOnInterface];
#endif
                        
                        sleep(1);
                        [self _reinitializeConnection];
                        return;
                    }
                    
                    break;
                }
            }
        }
        
        debug_log("frame_fetch_queue terminated\n");
    });
}

- (kern_return_t)_transferFrameFromCamera {
    
    if (self->usb_camera_handle == NULL) {
        debug_log("an attempt was made to transfer a frame from an inactive device\n");
        return KERN_FAILURE;
    }
    
    // Ask the device for an image
    kern_return_t ret;
    if ((ret = [self _requestFrameFromCamera]) != KERN_SUCCESS) {
        debug_log("failed to transfer frame from device\n");
        return ret;
    }

    int expected_transaction_len = self.transferFrameSize.width * self.transferFrameSize.height * 2;
    uint8_t transfer_buf[expected_transaction_len];
    
    int total_bytes_transferred = 0;
    while (total_bytes_transferred < expected_transaction_len) {
        
        uint32_t max_transfer_len = expected_transaction_len - total_bytes_transferred;
        int current_chunk_bytes_transferred = 0;
        
        if ((ret = libusb_bulk_transfer(self->usb_camera_handle, 0x81, &transfer_buf[total_bytes_transferred], max_transfer_len, &current_chunk_bytes_transferred, 250)) != KERN_SUCCESS) {
            debug_log("libusb_bulk_transfer failed after %d bytes out of %d: %s\n", total_bytes_transferred, expected_transaction_len, libusb_strerror((libusb_error)ret));
            
            return ret;
        }
        
        total_bytes_transferred += current_chunk_bytes_transferred;
    }
    
    pthread_mutex_lock(&self->raw_transfer_frame_mutex);
    if (total_bytes_transferred <= expected_transaction_len) {
        memcpy(self->raw_transfer_frame_buf, transfer_buf, total_bytes_transferred);
    }
    else {
        // This shouldn't be possible to hit, but just in case
        debug_log("data copied from the device is too large: received %d bytes\n", total_bytes_transferred);
        return KERN_FAILURE;
    }
    pthread_mutex_unlock(&self->raw_transfer_frame_mutex);
    
    dispatch_async(self->frame_processing_queue, ^{
        [self _processIngestedFrameWithLength:total_bytes_transferred];
    });
    
    return KERN_SUCCESS;
}

- (void)_processIngestedFrameWithLength:(int)length {
    
    self->camera_reported_frame_count = self->raw_transfer_frame_buf[self.frameCounterFieldOffset];
    
    switch (self->raw_transfer_frame_buf[self.frameTypeFieldOffset]) {
            
        case SEEK_FRAME_TYPE_GRADIENT_CALIBRATION: {
            
            break;

            debug_log("received gradient correction frame\n");
            self->raw_transfer_frame.copyTo(self->gradient_correction_frame);
            self->gradient_correction_frame = 0x4000 + self->gradient_correction_frame;
            
            break;
        }
            
        case SEEK_FRAME_TYPE_SHARPNESS_CALIBRATION: {
            
            break;

            debug_log("received sharpness correction frame\n");
            
            double f_min;
            cv::minMaxLoc(self->raw_transfer_frame, NULL, &f_min);
            
            self->raw_transfer_frame.copyTo(self->sharpness_correction_frame);
            
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
            
//            debug_log("received flat scene correction frame\n");
            self->raw_transfer_frame.copyTo(self->fsc_calibration_frame);
            self->fsc_calibration_frame = 0x4000 - self->fsc_calibration_frame;
            
            break;
        }
            
        case SEEK_FRAME_TYPE_DP_CALIBRATION: {
            
            debug_log("received dead pixel calibration frame\n");
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
            debug_log("received unknown frame type: %d\n", self->raw_transfer_frame_buf[self.frameTypeFieldOffset]);
            self->tx_error_count += 1;
            
            // Handle a case where a huge amount of unknown frame types have come in without ever seeing a valid one
            if (self->tx_error_count >= 100) {
                
                self.frameCount = 0;
                debug_log("data read issue? no valid frames coming through\n");
                [self _performDeviceInitialization];
                return;
            }
            
            break;
        }
    }
}

cv::Mat findPerimeter(const cv::Mat& binaryImage, int perimeter_kernel_size) {
    
    cv::Mat bwImage = binaryImage.clone();
    
    cv::medianBlur(bwImage, bwImage, 3); // Kernel size 3x3 -- / 2
    
    cv::Mat perimeter = cv::Mat::zeros(bwImage.size(), CV_8UC1);
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(perimeter_kernel_size, perimeter_kernel_size));
    
    cv::Mat dilated;
    cv::dilate(bwImage, dilated, kernel);
    
    cv::Mat eroded;
    cv::erode(bwImage, eroded, kernel);
    
    cv::subtract(dilated, eroded, perimeter);
    return perimeter;
}

- (void)_processIngestedImageFrame {
    
    pthread_mutex_lock(&self->raw_transfer_frame_mutex);
    cv::Mat intermediary_frame;
    self->raw_transfer_frame.copyTo(intermediary_frame);
    pthread_mutex_unlock(&self->raw_transfer_frame_mutex);

    if (!self->fsc_calibration_frame.empty()) {
        intermediary_frame += self->fsc_calibration_frame;
    }
    
    if (self->dead_pixel_mask.empty()) {
        debug_log("processing image while without dead pixel correction!\n");
    }
    else {
        // Apply dead pixel mask
        intermediary_frame.copyTo(intermediary_frame, dead_pixel_mask);
        for (int i = 0; i < self->dead_pixels.size(); i++) {
            cv::Point pixel = self->dead_pixels[i];
            intermediary_frame.at<uint16_t>(pixel) = [self _getAdjacentPixelMeanAtPoint:pixel fromImage:intermediary_frame deadPixelMarker:0xffff];
        }
    }
    
    // TODO: Account for drift, or exclude pixels that were not corrected via DPC from influencing exposure
    intermediary_frame = intermediary_frame(cv::Rect(0, 4, 201, 150));
    
    cv::Mat exposure_dead_pixel_mask = (intermediary_frame == 65535);
    cv::Mat exposure_dead_pixel_corrected_frame;
    cv::inpaint(intermediary_frame, exposure_dead_pixel_mask, exposure_dead_pixel_corrected_frame, 1, cv::INPAINT_TELEA);
    
    if (self.exposureMinThreshold == -1 || self.lockExposure == NO) {
        cv::minMaxLoc(exposure_dead_pixel_corrected_frame, &_exposureMinThreshold, &_exposureMaxThreshold);
        self->exposure_multiplier = 65535.0 / (self.exposureMaxThreshold - self.exposureMinThreshold);
    }
    
    for (int y = 0; y < exposure_dead_pixel_corrected_frame.rows; y++) {
        for (int x = 0; x < exposure_dead_pixel_corrected_frame.cols; x++) {
            
            uint16_t pixel_value = exposure_dead_pixel_corrected_frame.at<uint16_t>(y, x);
            if (pixel_value > self.exposureMaxThreshold) {
                pixel_value = 65535;
            }
            else if (pixel_value < self.exposureMinThreshold) {
                pixel_value = 0;
            }
            else {
                pixel_value = (pixel_value - self.exposureMinThreshold) * self->exposure_multiplier;
            }

            exposure_dead_pixel_corrected_frame.at<uint16_t>(y, x) = pixel_value;
        }
    }
    
    intermediary_frame = exposure_dead_pixel_corrected_frame;
    
    // The first frame min value may be 0. If so, reset it so that
    // min/max is recalculated on the next frame
    if (self.exposureMinThreshold == 0) {
        self.exposureMinThreshold = -1;
    }

    // Convert to 1 channel grayscale
    cv::Mat frame_one_channel;
    intermediary_frame.convertTo(frame_one_channel, CV_8UC1, 1.0 / 256.0);
    
    
//    [self _applySmoothingToFrame:frame_one_channel usingAccumulator:self->smoothing_accumulator alpha:0.50];
    
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
    
    // Adjust size
    cv::resize(frame_three_channel, frame_three_channel, cv::Size(), self.scaleFactor, self.scaleFactor, cv::INTER_LINEAR);
    
    // Edge detection
    cv::Mat erosion_kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(4, 4));
    if (self.edgeDetection) {
        
        cv::Mat edge_detect_blur_one_channel;
        cv::morphologyEx(frame_one_channel, edge_detect_blur_one_channel, cv::MORPH_ERODE, erosion_kernel);
        
        cv::resize(edge_detect_blur_one_channel, edge_detect_blur_one_channel, cv::Size(), self.scaleFactor, self.scaleFactor, cv::INTER_LINEAR);
        cv::GaussianBlur(edge_detect_blur_one_channel, edge_detect_blur_one_channel, cv::Size(3, 3), 0);

        cv::Mat edges = findPerimeter(edge_detect_blur_one_channel, self.edgeDetectionPerimeterSize);
        cv::Mat edgeOverlay = cv::Mat::zeros(edges.size(), edges.type());
        edges.copyTo(edgeOverlay, edges);
        
        [self _applySmoothingToFrame:edgeOverlay usingAccumulator:self->edge_accumulator alpha:0.90];
        cv::addWeighted(frame_three_channel, 1, edgeOverlay, 0.90, 0, frame_three_channel);
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
    
    if (self.performLastPassErosion) {
        cv::morphologyEx(frame_three_channel, frame_three_channel, cv::MORPH_ERODE, erosion_kernel);
    }
    
    // Apply color map
    if (self.opencvColormap >= 0) {
        
        // User specified an opencv colormap
        cv::applyColorMap(frame_three_channel, frame_three_channel, self.opencvColormap);
    }
    else {
        // No colormap specified, use one that is similar to Seek's Tyrian colormmap
        cv::applyColorMap(frame_three_channel, frame_three_channel, tyrian_color_map());
    }

    // Send processed frame to delegate
    [self.delegate seekCamera:self sentFrame:[self _imageFromPixelData:frame_three_channel.data width:frame_three_channel.cols height:frame_three_channel.rows]];
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
    
    if (!self->renderedBitmap || self->renderedBitmap.size.width != width) {
        self->renderedBitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:3 hasAlpha:0 isPlanar:0 colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:0 bytesPerRow:width * 3 bitsPerPixel:24];
        
        self->renderedImageOutput =  [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
        [self->renderedImageOutput addRepresentation:self->renderedBitmap];
    }
    
    memcpy([self->renderedBitmap bitmapData], source, width * height * 3);
    NSImage *outputImage = [self->renderedImageOutput copy];
    
    return outputImage;
}
#else
- (UIImage *)_uiimageFromPixelData:(unsigned char *)source width:(int)width height:(int)height {
    
    NSData *data = [NSData dataWithBytes:source length:width * height * 3];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(960, 720, 8, 24, width * 3, colorSpace, kCGImageAlphaNone, provider, NULL, false, kCGRenderingIntentDefault);
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}
#endif

- (void)_buildDeadPixelMask {
    
    self->dead_pixel_mask = cv::Mat();
    cv::Mat converted_frame;
    self->raw_transfer_frame.convertTo(converted_frame, CV_32FC1);
    
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

- (void)_applySmoothingToFrame:(const cv::Mat&)frame usingAccumulator:(cv::Mat&)accumulator alpha:(double)alpha {
    
    if (accumulator.empty()) {
        frame.convertTo(accumulator, CV_32F);
    }
    
    cv::accumulateWeighted(frame, accumulator, alpha);
    accumulator.convertTo(frame, frame.type());
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
