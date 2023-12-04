//
//  ViewController.m
//  SeekMosaicViewer
//
//  Created by Ethan Arbuckle
//

#import "ViewController.h"

@interface ViewController () {
    NSDate *sessionStartDate;
}

@end


@implementation ViewController

- (void)viewDidAppear {
    [super viewDidAppear];
    
    self.seekCamera = [[SeekMosaicCamera alloc] initWithDelegate:self];
    self.seekCamera.scaleFactor = 3;
    
    
    // Setup window and image view to contain the thermal images
    self.view.window.minSize = NSMakeSize(970, 730);
    self.thermalImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 960, 720)];
    [self.thermalImageView setWantsLayer:YES];
    [[self.thermalImageView layer] setBackgroundColor:[NSColor darkGrayColor].CGColor];
    [self.view addSubview:self.thermalImageView];
    
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
    
    [self.seekCamera start];
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

    NSSlider *minSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, minLabel.frame.origin.y - controlSpacing, sliderWidth, sliderHeight) minValue:1 maxValue:250 action:@selector(minSliderChanged:)];
    minSlider.floatValue = self.seekCamera.edgeDetectioneMinThreshold;
    [parentView addSubview:minSlider];

    NSTextField *maxLabel = [self labelWithText:@"Exposure Ceil" frame:NSMakeRect(controlSpacing, (minSlider.frame.origin.y - controlSpacing - labelHeight) + 5, sliderWidth, labelHeight)];
    maxLabel.backgroundColor = [NSColor clearColor];
    [parentView addSubview:maxLabel];

    NSSlider *maxSlider = [self sliderWithFrame:NSMakeRect(controlSpacing, maxLabel.frame.origin.y - controlSpacing, sliderWidth, sliderHeight) minValue:1 maxValue:250 action:@selector(maxSliderChanged:)];
    maxSlider.floatValue = self.seekCamera.edgeDetectionMaxThreshold;
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
    [toggleShutterButton setBezelColor:[NSColor lightGrayColor]];//:NO];
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
    [self.seekCamera setExposureMinThreshold:[sender doubleValue]];
}

- (void)maxSliderChanged:(NSSlider *)sender {
    [self.seekCamera setExposureMaxThreshold:[sender doubleValue]];
}

- (void)edgeDetectionSwitchToggled:(NSSwitch *)sender {
    self.seekCamera.edgeDetection = sender.state == NSControlStateValueOn;
}

- (void)autoShutterSwitchToggled:(NSSwitch *)sender {
    self.seekCamera.shutterMode = sender.state == NSControlStateValueOn ? SeekCameraShutterModeAuto : SeekCameraShutterModeManual;
}

- (void)toggleShutter {
    
    if (self.seekCamera) {
        [self.seekCamera toggleShutter];
    }
}

- (void)viewDidLayout {
    
    int windowHeight = self.view.window.frame.size.height;
    int imageViewHeight = self.thermalImageView.frame.size.height;
    
    CGRect thermalImageViewFrame = self.thermalImageView.frame;
    thermalImageViewFrame.origin.y = (windowHeight / 2) - (imageViewHeight / 2);
    self.thermalImageView.frame = thermalImageViewFrame;
}

- (void)handleColormapButton:(NSButton *)sender {
    
    if (sender.tag == 23) {
        [self.seekCamera resetExposureThresholds];
        return;
    }
    
    self.seekCamera.opencvColormap = (int)sender.tag;
}

- (void)seekCameraDidConnect:(SeekMosaicCamera *)camera {
    NSLog(@"Connected to device: %@", camera.serialNumber);
    self->sessionStartDate = [NSDate now];
}

- (void)seekCameraDidDisconnect:(SeekMosaicCamera *)camera {
    NSLog(@"Disconnected from device: %@", camera.serialNumber);
}

- (void)seekCamera:(SeekMosaicCamera *)camera sentFrame:(NSImage *)frame {
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        self.thermalImageView.image = frame;
        
        if (camera.frameCount == 0) {
            self->sessionStartDate = [NSDate now];
        }
        else if (camera.frameCount > 20) {
            
            NSTimeInterval streamDuration = [[NSDate now] timeIntervalSinceDate:self->sessionStartDate];
            float fps = camera.frameCount / streamDuration;
            NSAttributedString *attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%.2f fps", fps] attributes:@{
                NSStrokeWidthAttributeName: @-3.0,
                NSStrokeColorAttributeName:[NSColor blackColor],
                NSForegroundColorAttributeName:[NSColor whiteColor],
                NSFontAttributeName: [NSFont fontWithName:@"HelveticaNeue-Bold" size:34]
            }];
            
            self.fpsTextView.placeholderAttributedString = attr;
        }
        
        if ((camera.frameCount % 1000) == 0) {
            [camera toggleShutter];
        }
    });
}

@end
