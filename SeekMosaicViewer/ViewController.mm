//
//  ViewController.m
//  SeekMosaicViewer
//
//  Created by Ethan Arbuckle
//

#import <opencv2/opencv.hpp>
#import "ViewController.h"
#import "SeekDeviceDiscovery.h"

@interface ViewController () {
    NSDate *sessionStartDate;
    SeekDeviceDiscovery *deviceDiscoverer;
    NSMutableArray *activeDevices;
    cv::Mat root_accumulator;
    int combined_frame_count;
}

@end

int x_offset = 0;
int y_offset = 0;

@implementation ViewController

- (void)viewDidAppear {
    [super viewDidAppear];
    
    self->activeDevices = [[NSMutableArray alloc] init];
    self->deviceDiscoverer = [[SeekDeviceDiscovery alloc] init];
    
    __block typeof(self) weakSelf = self;
    [self->deviceDiscoverer addDiscoveryHandler:^(SeekDevice * _Nonnull device) {
        
        [device setDelegate:weakSelf];
        //        [device setAccum:weakSelf->root_accumulator];
        [device start];
        
        [weakSelf->activeDevices addObject:device];
    }];
    
    // Setup window and image view to contain the thermal images
    self.view.window.minSize = NSMakeSize(970, 730);
    self.thermalImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 960, 720)];
    [self.thermalImageView setWantsLayer:YES];
    [[self.thermalImageView layer] setBackgroundColor:[NSColor clearColor].CGColor];
    self.thermalImageView.alphaValue = 1;//0.50;
    self.thermalImageView.imageScaling = NSImageScaleNone;
    [self.view addSubview:self.thermalImageView];
    
    //    self.view.window.minSize = NSMakeSize(970, 730);
    self.thermalImageView2 = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 960, 720)];
    [self.thermalImageView2 setWantsLayer:YES];
    [[self.thermalImageView2 layer] setBackgroundColor:[NSColor clearColor].CGColor];
    self.thermalImageView2.alphaValue = 0.50;
    self.thermalImageView2.imageScaling = NSImageScaleNone;
    [self.view addSubview:self.thermalImageView2];
    
    self.fpsTextView = [[NSTextField alloc] initWithFrame:NSMakeRect(self.thermalImageView.frame.size.width - 180, 5, 170, 50)];
    self.fpsTextView.backgroundColor = [NSColor clearColor];
    self.fpsTextView.alignment = NSTextAlignmentRight;
    self.fpsTextView.bordered = NO;
    self.fpsTextView.enabled = NO;
    [self.thermalImageView addSubview:self.fpsTextView];
    
    NSView *colorMapContainerView = [[NSView alloc] initWithFrame:NSMakeRect(self.thermalImageView.frame.size.width + 20, 10, 300, 220)];
    [colorMapContainerView setWantsLayer:YES];
    colorMapContainerView.layer.backgroundColor = [NSColor lightGrayColor].CGColor;
    [self addColormapButtonsToView:colorMapContainerView];
    [self.view addSubview:colorMapContainerView];
    
    NSView *edgeDetectionContainerView = [[NSView alloc] initWithFrame:NSMakeRect(self.thermalImageView.frame.size.width + 20, colorMapContainerView.frame.origin.y + colorMapContainerView.frame.size.height + 10, 300, 200)];
    [edgeDetectionContainerView setWantsLayer:YES];
    edgeDetectionContainerView.layer.backgroundColor = [NSColor lightGrayColor].CGColor;
    [self addControlsToView:edgeDetectionContainerView];
    [self.view addSubview:edgeDetectionContainerView];
    
    self->combined_frame_count = 0;
    
    [self->deviceDiscoverer startDiscovery];
}

- (void)addColormapButtonsToView:(NSView *)parentView {
    
    NSInteger firstColormapValue = 0;
    NSInteger lastColormapValue = 21;
    NSInteger numberOfButtons = lastColormapValue - firstColormapValue + 3;
    NSInteger buttonsPerRow = 4;
    NSInteger buttonSpacing = 10;
    
    NSInteger numberOfRows = (NSInteger)ceil((double)numberOfButtons / buttonsPerRow);
    NSSize buttonSize = NSMakeSize((parentView.bounds.size.width - (buttonSpacing * (buttonsPerRow + 1))) / buttonsPerRow,
                                   (parentView.bounds.size.height - (buttonSpacing * (numberOfRows + 1))) / numberOfRows);
    
    for (NSInteger i = 0; i < numberOfButtons; i++) {
        
        NSInteger column = i % buttonsPerRow;
        NSInteger row = i / buttonsPerRow;
        
        CGFloat yPosition = parentView.bounds.size.height - (row + 1) * (buttonSize.height + buttonSpacing);
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(column * (buttonSize.width + buttonSpacing) + buttonSpacing, yPosition, buttonSize.width, buttonSize.height)];
        
        [button setWantsLayer:YES];
        button.layer.backgroundColor = [NSColor darkGrayColor].CGColor;
        if (i == lastColormapValue + 1) {
            button.title = @"tyrian";
        }
        else if (i == lastColormapValue + 2) {
            button.title = @"r/ AEL";
        }
        else {
            button.title = [NSString stringWithFormat:@"# %ld", i + firstColormapValue];
        }
        button.tag = i + firstColormapValue;
        button.target = self;
        button.action = @selector(handleColormapButton:);
        [parentView addSubview:button];
    }
}

- (void)addControlsToView:(NSView *)parentView {
    
    CGFloat sliderWidth = parentView.frame.size.width - 20;
    CGFloat sliderHeight = 25.0;
    CGFloat switchWidth = 80.0;
    CGFloat switchHeight = 30.0;
    CGFloat labelHeight = 30.0;
    CGFloat controlSpacing = 10.0;
    
    // Create labels and controls
    NSTextField *minLabel = [self labelWithText:@"Exposure Floor" frame:NSMakeRect(controlSpacing, parentView.bounds.size.height - labelHeight - controlSpacing, sliderWidth, labelHeight)];
    minLabel.backgroundColor = [NSColor clearColor];
    [parentView addSubview:minLabel];
    
    NSSlider *minSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, minLabel.frame.origin.y - controlSpacing, sliderWidth, sliderHeight) minValue:1 maxValue:65535 action:@selector(minSliderChanged:)];
    minSlider.floatValue = self.seekCamera.exposureMinThreshold;
    [parentView addSubview:minSlider];
    
    NSTextField *maxLabel = [self labelWithText:@"Exposure Ceil" frame:NSMakeRect(controlSpacing, (minSlider.frame.origin.y - controlSpacing - labelHeight) + 5, sliderWidth, labelHeight)];
    maxLabel.backgroundColor = [NSColor clearColor];
    [parentView addSubview:maxLabel];
    
    NSSlider *maxSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, maxLabel.frame.origin.y - controlSpacing, sliderWidth, sliderHeight) minValue:1 maxValue:250 action:@selector(maxSliderChanged:)];
    maxSlider.floatValue = self.seekCamera.exposureMaxThreshold;
    [parentView addSubview:maxSlider];
    
    NSTextField *edgeDetectionLabel = [self labelWithText:@"Edge Detection:" frame:NSMakeRect(controlSpacing, (maxSlider.frame.origin.y - sliderHeight - controlSpacing) - 5, sliderWidth, labelHeight)];
    [parentView addSubview:edgeDetectionLabel];
    
    NSSwitch *edgeDetectionSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(controlSpacing + switchWidth + controlSpacing, maxSlider.frame.origin.y - switchHeight - 5, switchWidth, switchHeight)];
    [edgeDetectionSwitch setTarget:self];
    [edgeDetectionSwitch setAction:@selector(edgeDetectionSwitchToggled:)];
    edgeDetectionSwitch.state = self.seekCamera.edgeDetection ? NSControlStateValueOn : NSControlStateValueOff;
    [parentView addSubview:edgeDetectionSwitch];
    
    NSTextField *autoShutterLabel = [self labelWithText:@"Auto Shutter:" frame:NSMakeRect(controlSpacing, edgeDetectionSwitch.frame.origin.y - switchHeight - controlSpacing, sliderWidth, labelHeight)];
    [parentView addSubview:autoShutterLabel];
    
    NSSwitch *autoShutterSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(controlSpacing + switchWidth + controlSpacing, edgeDetectionSwitch.frame.origin.y - switchHeight - 5, switchWidth, switchHeight)];
    [autoShutterSwitch setTarget:self];
    [autoShutterSwitch setAction:@selector(autoShutterSwitchToggled:)];
    autoShutterSwitch.state = self.seekCamera.shutterMode == SeekCameraShutterModeAuto ? NSControlStateValueOn : NSControlStateValueOff;
    [parentView addSubview:autoShutterSwitch];
    
    NSButton *toggleShutterButton = [[NSButton alloc] initWithFrame:NSMakeRect(controlSpacing, autoShutterSwitch.frame.origin.y - switchHeight - 10, 130, 45)];
    [toggleShutterButton setBezelColor:[NSColor lightGrayColor]];
    toggleShutterButton.title = @"Toggle Shutter";
    toggleShutterButton.target = self;
    toggleShutterButton.action = @selector(toggleShutter);
    [parentView addSubview:toggleShutterButton];
}

- (NSSlider *)sliderWithFrame:(NSRect)frame minValue:(double)minValue maxValue:(double)maxValue action:(SEL)action {
    NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];
    [slider setMinValue:minValue];
    [slider setMaxValue:maxValue];
    [slider setTarget:self];
    [slider setNumberOfTickMarks:50];
    [slider setAction:action];
    return slider;
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

- (void)minSliderChanged:(NSSlider *)sender {
    x_offset = [sender doubleValue];
    //    [self.seekCamera setExposureMinThreshold:[sender doubleValue]];
}

- (void)maxSliderChanged:(NSSlider *)sender {
    //    offset = [sender doubleValue];
    y_offset = [sender doubleValue];
    //    [self.seekCamera setExposureMaxThreshold:[sender doubleValue]];
}

- (void)edgeDetectionSwitchToggled:(NSSwitch *)sender {
    self.seekCamera.edgeDetection = sender.state == NSControlStateValueOn;
}

- (void)autoShutterSwitchToggled:(NSSwitch *)sender {
    self.seekCamera.shutterMode = sender.state == NSControlStateValueOn ? SeekCameraShutterModeAuto : SeekCameraShutterModeManual;
}

- (void)toggleShutter {
    
    for (SeekDevice *device in self->activeDevices) {
        [device toggleShutter];
    }
}

- (void)viewDidLayout {
    
    int windowHeight = self.view.window.frame.size.height;
    int imageViewHeight = self.thermalImageView.frame.size.height;
    
    CGRect thermalImageViewFrame = self.thermalImageView.frame;
    thermalImageViewFrame.origin.y = (windowHeight / 2) - (imageViewHeight / 2);
    self.thermalImageView.frame = thermalImageViewFrame;
    
    thermalImageViewFrame.origin.y = 20;
    self.thermalImageView2.frame = thermalImageViewFrame;
}

- (void)handleColormapButton:(NSButton *)sender {
    
    for (SeekDevice *device in self->activeDevices) {
        
        if (sender.tag == 23) {
            [device resetExposureThresholds];
            return;
        }
        
        device.opencvColormap = (int)sender.tag;
    }
}

- (void)seekCameraDidConnect:(SeekDevice *)camera {
    NSLog(@"Connected to device: %@", camera.serialNumber);
    self->sessionStartDate = [NSDate now];
}

- (void)seekCameraDidDisconnect:(SeekDevice *)camera {
    NSLog(@"Disconnected from device: %@", camera.serialNumber);
}

- (NSImage *)offsetImage:(NSImage *)image xOffset:(CGFloat)xOffset yOffset:(CGFloat)yOffset {
    // Create a new NSImage with the same size as the original
    NSImage *offsetImage = [[NSImage alloc] initWithSize:[image size]];
    
    [offsetImage lockFocus];
    
    // Calculate the new origin point
    NSRect newRect = NSMakeRect(xOffset, yOffset, [image size].width, [image size].height);
    
    // Draw the original image in the new position
    [image drawInRect:newRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
    
    [offsetImage unlockFocus];
    
    return offsetImage;
}

- (void)seekCamera:(SeekDevice *)camera sentFrame:(NSImage *)frame {
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        if ([camera.serialNumber containsString:@"21D"]) {
            
            CGFloat xOffset = x_offset;//camera.edgeDetectioneMinThreshold; // Adjust as necessary
            CGFloat yOffset = y_offset;  // Adjust if vertical offset is also needed
            //            NSImage *adjustedImage = [self offsetImage:frame xOffset:xOffset yOffset:yOffset];
            //            NSLog(@"2 %@", self.thermalImageView2);
            NSRect baseFrameRect = self.thermalImageView.frame;
            NSRect overlayedFrameRect = self.thermalImageView2.frame;
            overlayedFrameRect.origin.x = baseFrameRect.origin.x + x_offset;
            overlayedFrameRect.origin.y = baseFrameRect.origin.y + y_offset;
            self.thermalImageView2.frame = overlayedFrameRect;
            self.thermalImageView2.image = frame;
        }
        else {
            //            NSLog(@"1 %@", self.thermalImageView);
            self.thermalImageView.image = frame;
        }
        
        if (camera.frameCount == 0) {
            self->sessionStartDate = [NSDate now];
        }
        else if (camera.frameCount > 20) {
            
            self->combined_frame_count += 1;
            NSTimeInterval streamDuration = [[NSDate now] timeIntervalSinceDate:self->sessionStartDate];
            float fps = self->combined_frame_count / streamDuration;
            NSAttributedString *attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%.2f fps", fps] attributes:@{
                NSStrokeWidthAttributeName: @-3.0,
                NSStrokeColorAttributeName:[NSColor blackColor],
                NSForegroundColorAttributeName:[NSColor whiteColor],
                NSFontAttributeName: [NSFont fontWithName:@"HelveticaNeue-Bold" size:34]
            }];
            
            self.fpsTextView.placeholderAttributedString = attr;
        }
        
        for (SeekDevice *device in self->activeDevices) {
            if (device.shutterMode == SeekCameraShutterModeManual && (device.frameCount % 1000) == 0) {
                [device toggleShutter];
            }
        }
    });
}

@end
