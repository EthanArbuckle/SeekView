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
    NSMutableArray *activeDevices;
    int combined_frame_count;
    SeekCameraShutterMode currentShutterMode;
    BOOL edgeDetectionEnabled;
    BOOL lockExposure;
    int exposureMinThreshold;
    int exposureMaxThreshold;
    int edgeDetectionPerimeterSize;
    int blurFactor;
    BOOL performLastPassErosion;
    NSMutableAttributedString *fpsLabelString;
}

@property (nonatomic, retain) NSSlider *exposureMinThresholdSlider;
@property (nonatomic, retain) NSSlider *exposureMaxThresholdSlider;
@property (nonatomic, retain) NSSlider *guassianBlurSlider;
@property (nonatomic, retain) NSSlider *edgeDetectionPerimeterSlider;

@end

@implementation ViewController

- (void)viewDidAppear {
    [super viewDidAppear];
    
    self->activeDevices = [[NSMutableArray alloc] init];
    self->currentShutterMode = SeekCameraShutterModeAuto;
    self->edgeDetectionEnabled = NO;
    self->lockExposure = YES;
    self->exposureMaxThreshold = -1;
    self->exposureMinThreshold = -1;
    self->blurFactor = -1;
    self->edgeDetectionPerimeterSize = -1;
    self->performLastPassErosion = YES;
    
    self->fpsLabelString = [[NSMutableAttributedString alloc] initWithString:@"..." attributes:@{
        NSStrokeWidthAttributeName: @-3.0,
        NSStrokeColorAttributeName:[NSColor blackColor],
        NSForegroundColorAttributeName:[NSColor whiteColor],
        NSFontAttributeName: [NSFont fontWithName:@"HelveticaNeue-Bold" size:34]
    }];
    
    [[SeekDeviceDiscovery discoverer] addDiscoveryHandler:^(SeekDevice * _Nonnull device) {
        
        [device setDelegate:self];
        device.shutterMode = self->currentShutterMode;
        device.edgeDetection = self->edgeDetectionEnabled;
        device.lockExposure = self->lockExposure;
        device.performLastPassErosion = self->performLastPassErosion;
        [device start];
    }];
    
    // Setup window and image view to contain the thermal images
    self.view.window.minSize = NSMakeSize(970, 730);
    self.thermalImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 960, 720)];
    [self.thermalImageView setWantsLayer:YES];
    [[self.thermalImageView layer] setBackgroundColor:[NSColor clearColor].CGColor];
    self.thermalImageView.alphaValue = 0.75;
    self.thermalImageView.imageScaling = NSImageScaleNone;
    [self.view addSubview:self.thermalImageView];
    
    //    self.view.window.minSize = NSMakeSize(970, 730);
    self.thermalImageView2 = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 960, 720)];
    [self.thermalImageView2 setWantsLayer:YES];
    [[self.thermalImageView2 layer] setBackgroundColor:[NSColor clearColor].CGColor];
    self.thermalImageView2.alphaValue = 0.75;
    self.thermalImageView2.imageScaling = NSImageScaleNone;
    [self.view addSubview:self.thermalImageView2];
    
    self.fpsTextView = [[NSTextField alloc] initWithFrame:NSMakeRect(self.thermalImageView.frame.size.width - 180, 5, 170, 50)];
    self.fpsTextView.backgroundColor = [NSColor clearColor];
    self.fpsTextView.alignment = NSTextAlignmentRight;
    self.fpsTextView.bordered = NO;
    self.fpsTextView.enabled = NO;
    self.fpsTextView.placeholderAttributedString = self->fpsLabelString;
    [self.thermalImageView addSubview:self.fpsTextView];
    
    NSView *colorMapContainerView = [[NSView alloc] initWithFrame:NSMakeRect(self.thermalImageView.frame.size.width + 20, 10, 300, 240)];
    [colorMapContainerView setWantsLayer:YES];
    colorMapContainerView.layer.backgroundColor = [NSColor lightGrayColor].CGColor;
    [self addColormapButtonsToView:colorMapContainerView];
    [self.view addSubview:colorMapContainerView];
    
    NSView *edgeDetectionContainerView = [[NSView alloc] initWithFrame:NSMakeRect(self.thermalImageView.frame.size.width + 20, colorMapContainerView.frame.origin.y + colorMapContainerView.frame.size.height + 10, 300, 260)];
    [edgeDetectionContainerView setWantsLayer:YES];
    edgeDetectionContainerView.layer.backgroundColor = [NSColor lightGrayColor].CGColor;
    [self addControlsToView:edgeDetectionContainerView];
    [self.view addSubview:edgeDetectionContainerView];
    
    self->combined_frame_count = 0;
    
    [[SeekDeviceDiscovery discoverer] startDiscovery];
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
    
    self.exposureMinThresholdSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, minLabel.frame.origin.y - controlSpacing, sliderWidth, sliderHeight) minValue:100 maxValue:16500 action:@selector(minSliderChanged:)];
    self.exposureMinThresholdSlider.floatValue = self->exposureMinThreshold;
    [parentView addSubview:self.exposureMinThresholdSlider];
    
    NSTextField *maxLabel = [self labelWithText:@"Exposure Ceil" frame:NSMakeRect(controlSpacing, (self.exposureMinThresholdSlider.frame.origin.y - controlSpacing - labelHeight) + 5, sliderWidth, labelHeight)];
    maxLabel.backgroundColor = [NSColor clearColor];
    [parentView addSubview:maxLabel];
    
    self.exposureMaxThresholdSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, maxLabel.frame.origin.y - controlSpacing, sliderWidth, sliderHeight) minValue:15000 maxValue:32000 action:@selector(maxSliderChanged:)];
    self.exposureMaxThresholdSlider.floatValue = self->exposureMaxThreshold;
    [parentView addSubview:self.exposureMaxThresholdSlider];
    
    self.guassianBlurSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, controlSpacing + sliderHeight, sliderWidth, sliderHeight) minValue:0 maxValue:9 action:@selector(handleGuassianBlurSliderChanges:)];
    self.guassianBlurSlider.intValue = self->blurFactor;
    self.guassianBlurSlider.altIncrementValue = 1;
    self.guassianBlurSlider.numberOfTickMarks = 7;
    [parentView addSubview:self.guassianBlurSlider];
    
    NSTextField *blurSliderText = [self labelWithText:@"Blur Factor" frame:NSMakeRect(controlSpacing, (self.guassianBlurSlider.frame.origin.y - controlSpacing - labelHeight) + 5, sliderWidth, labelHeight)];
    blurSliderText.backgroundColor = [NSColor clearColor];
    [parentView addSubview:blurSliderText];
    
    self.edgeDetectionPerimeterSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, controlSpacing, sliderWidth, sliderHeight) minValue:1 maxValue:10 action:@selector(handleEdgeDetectionParameterSlider:)];
    self.edgeDetectionPerimeterSlider.intValue = self->edgeDetectionPerimeterSize;
    self.edgeDetectionPerimeterSlider.altIncrementValue = 1;
    self.edgeDetectionPerimeterSlider.numberOfTickMarks = 10;
    [parentView addSubview:self.edgeDetectionPerimeterSlider];
    
    NSTextField *edgePerimeterSizeText = [self labelWithText:@"Edge Perimeter Size" frame:NSMakeRect(controlSpacing, (self.edgeDetectionPerimeterSlider.frame.origin.y - controlSpacing - labelHeight) + 5, sliderWidth, labelHeight)];
    edgePerimeterSizeText.backgroundColor = [NSColor clearColor];
    [parentView addSubview:edgePerimeterSizeText];
    
    
    NSTextField *edgeDetectionLabel = [self labelWithText:@"Edge Detection:" frame:NSMakeRect(controlSpacing, (self.exposureMaxThresholdSlider.frame.origin.y - sliderHeight - controlSpacing) - 5, sliderWidth, labelHeight)];
    [parentView addSubview:edgeDetectionLabel];
    
    NSSwitch *edgeDetectionSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(controlSpacing + switchWidth + controlSpacing, self.exposureMaxThresholdSlider.frame.origin.y - switchHeight - 5, switchWidth, switchHeight)];
    [edgeDetectionSwitch setTarget:self];
    [edgeDetectionSwitch setAction:@selector(edgeDetectionSwitchToggled:)];
    edgeDetectionSwitch.state = self->edgeDetectionEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [parentView addSubview:edgeDetectionSwitch];
    
    NSTextField *autoShutterLabel = [self labelWithText:@"Auto Shutter:" frame:NSMakeRect(controlSpacing, edgeDetectionSwitch.frame.origin.y - switchHeight - controlSpacing, sliderWidth, labelHeight)];
    [parentView addSubview:autoShutterLabel];
    
    NSSwitch *autoShutterSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(controlSpacing + switchWidth + controlSpacing, edgeDetectionSwitch.frame.origin.y - switchHeight - 5, switchWidth, switchHeight)];
    [autoShutterSwitch setTarget:self];
    [autoShutterSwitch setAction:@selector(autoShutterSwitchToggled:)];
    autoShutterSwitch.state = self->currentShutterMode == SeekCameraShutterModeAuto ? NSControlStateValueOn : NSControlStateValueOff;
    [parentView addSubview:autoShutterSwitch];
    
    NSSwitch *lastPassErosionSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(controlSpacing + switchWidth + controlSpacing + 60, edgeDetectionSwitch.frame.origin.y - switchHeight - 5, switchWidth, switchHeight)];
    [lastPassErosionSwitch setTarget:self];
    [lastPassErosionSwitch setAction:@selector(handleLastPassErosionSwitch:)];
    lastPassErosionSwitch.state = self->performLastPassErosion ? NSControlStateValueOn : NSControlStateValueOff;
    [parentView addSubview:lastPassErosionSwitch];
    
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
    self->exposureMinThreshold = sender.floatValue;
    for (SeekDevice *device in self->activeDevices) {
        [device setExposureMinThreshold:[sender doubleValue]];
    }
}

- (void)maxSliderChanged:(NSSlider *)sender {
    self->exposureMaxThreshold = sender.floatValue;
    for (SeekDevice *device in self->activeDevices) {
        [device setExposureMaxThreshold:[sender doubleValue]];
    }
}

- (void)handleGuassianBlurSliderChanges:(NSSlider *)sender {
    
    int odd_slider_value = sender.intValue;
    if (odd_slider_value % 2 == 0) {
        odd_slider_value += 1;
        sender.intValue = odd_slider_value;
    }
    
    self->blurFactor = odd_slider_value;
    for (SeekDevice *device in self->activeDevices) {
        [device setBlurFactor:self->blurFactor];
    }
}

- (void)handleEdgeDetectionParameterSlider:(NSSlider *)sender {
    self->edgeDetectionPerimeterSize = sender.intValue;
    for (SeekDevice *device in self->activeDevices) {
        [device setEdgeDetectionPerimeterSize:self->edgeDetectionPerimeterSize];
    }
}

- (void)edgeDetectionSwitchToggled:(NSSwitch *)sender {
    self->edgeDetectionEnabled = sender.state == NSControlStateValueOn;
    
    for (SeekDevice *device in self->activeDevices) {
        device.edgeDetection = self->edgeDetectionEnabled;
    }
}

- (void)autoShutterSwitchToggled:(NSSwitch *)sender {
    self->currentShutterMode = sender.state == NSControlStateValueOn ? SeekCameraShutterModeAuto : SeekCameraShutterModeManual;
    
    for (SeekDevice *device in self->activeDevices) {
        device.shutterMode = self->currentShutterMode;
    }
}

- (void)handleLastPassErosionSwitch:(NSSwitch *)sender {
    self->performLastPassErosion = sender.state == NSControlStateValueOn;
    
    for (SeekDevice *device in self->activeDevices) {
        device.performLastPassErosion = self->performLastPassErosion;
    }
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
    
    thermalImageViewFrame.origin.x += 129;
    self.thermalImageView2.frame = thermalImageViewFrame;
}

- (void)handleColormapButton:(NSButton *)sender {
    
    for (SeekDevice *device in self->activeDevices) {
        
        if (sender.tag == 23) {
            
            self->exposureMinThreshold = -1;
            self->exposureMaxThreshold = -1;
            [device resetExposureThresholds];
            continue;
        }
        
        device.opencvColormap = (int)sender.tag;
    }
}

- (void)seekCameraDidConnect:(SeekDevice *)device {
    
    if ([self->activeDevices containsObject:device]) {
        debug_log("seekCameraDidConnect fired for a device already being tracked: %s\n", device.serialNumber.UTF8String);
        return;
    }
    
    [self->activeDevices addObject:device];
    NSLog(@"Connected to device: %@", device.serialNumber);
    self->sessionStartDate = [NSDate now];
    
    void (^updateLocalInfoAndUIComponents)(void) = ^void(void) {
        if (self->exposureMinThreshold == -1) {
            self->exposureMinThreshold = device.exposureMinThreshold;
            self.exposureMinThresholdSlider.floatValue = self->exposureMinThreshold;
        }
        
        if (self->exposureMaxThreshold == -1) {
            self->exposureMaxThreshold = device.exposureMaxThreshold;
            self.exposureMaxThresholdSlider.floatValue = self->exposureMaxThreshold;
        }
        
        if (self->blurFactor == -1) {
            self->blurFactor = device.blurFactor;
            self.guassianBlurSlider.floatValue = device.blurFactor;
        }
        
        if (self->edgeDetectionPerimeterSize == -1) {
            self->edgeDetectionPerimeterSize = device.edgeDetectionPerimeterSize;
            self.edgeDetectionPerimeterSlider.intValue = self->edgeDetectionPerimeterSize;
        }
    };

    if ([[NSThread currentThread] isMainThread]) {
        updateLocalInfoAndUIComponents();
    }
    else {
        dispatch_sync(dispatch_get_main_queue(), updateLocalInfoAndUIComponents);
    }
}

- (void)seekCameraDidDisconnect:(SeekDevice *)camera {
    if ([self->activeDevices containsObject:camera]) {
        NSLog(@"Disconnected from device: %@", camera.serialNumber);
        [self->activeDevices removeObject:camera];
    }
}

- (void)seekCamera:(SeekDevice *)camera sentFrame:(NSImage *)frame {
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        if ([camera.serialNumber containsString:@"21D"]) {
            self.thermalImageView2.image = frame;
        }
        else {
            self.thermalImageView.image = frame;
        }
        
        if (camera.frameCount == 0) {
            self->sessionStartDate = [NSDate now];
        }
        else if (camera.frameCount > 20) {
            
            self->combined_frame_count += 1;
            NSTimeInterval streamDuration = [[NSDate now] timeIntervalSinceDate:self->sessionStartDate];
            float fps = self->combined_frame_count / streamDuration;
            [self->fpsLabelString replaceCharactersInRange:NSMakeRange(0, self->fpsLabelString.string.length) withString:[NSString stringWithFormat:@"%.2f fps", fps]];
            [self.fpsTextView setPlaceholderAttributedString:self->fpsLabelString];
            
            if (self->exposureMinThreshold == -1) {
                self->exposureMinThreshold = camera.exposureMinThreshold;
                self->exposureMaxThreshold = camera.exposureMaxThreshold;
                
                self.exposureMinThresholdSlider.floatValue = self->exposureMinThreshold;
                self.exposureMaxThresholdSlider.floatValue = self->exposureMaxThreshold;
            }
        }
        
        if ([self->activeDevices count] > 1 && self->exposureMinThreshold > 0) {
            
            for (SeekDevice *device in self->activeDevices) {
                
                if (device.exposureMinThreshold != self->exposureMinThreshold) {
                    [device setExposureMinThreshold:self->exposureMinThreshold];
                }
                
                if (device.exposureMaxThreshold != self->exposureMaxThreshold) {
                    [device setExposureMaxThreshold:self->exposureMaxThreshold];
                }
            }
        }
    });
}

@end
