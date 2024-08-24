//
//  BeatColors.m
//  Beat
//
//  Created by Lauri-Matti Parppei on 27.5.2020.
//  Copyright © 2020 Lauri-Matti Parppei. All rights reserved.
//

#import "BeatColors.h"

@interface BeatColors ()
@property (nonatomic) NSDictionary *colorValues;
@end

@implementation BeatColors

+ (BeatColors*)sharedColors
{
	static BeatColors* sharedColors;
	if (!sharedColors) {
		sharedColors = BeatColors.new;
	}
	return sharedColors;
}

- (NSDictionary*)colorValues {
	if (_colorValues) return _colorValues;
	else _colorValues = @{
			 @"red" : [BeatColors colorWithRed:239 green:0 blue:73],
			 @"blue" : [BeatColors colorWithRed:0 green:129 blue:239],
			 @"green": [BeatColors colorWithRed:0 green:223 blue:121],
			 @"pink": [BeatColors colorWithRed:254 green:131 blue:223],
			 @"magenta": [BeatColors colorWithRed:236 green:0 blue:140],
			 @"gray": [BeatColors colorWithRed:128 green:128 blue:128],
			 @"grey": [BeatColors colorWithRed:128 green:128 blue:128], // for the illiterate
			 @"purple": [BeatColors colorWithRed:181 green:32 blue:218],
			 @"yellow": [BeatColors colorWithRed:251 green:200 blue:45],
             @"goldenrod": [BeatColors colorWithRed:215 green:148 blue:15],
             @"rose": [BeatColors colorWithRed:236 green:184 blue:152],
             @"buff": [BeatColors colorWithRed:118 green:100 blue:86],
             @"cherry": [BeatColors colorWithRed:236 green:90 blue:150],
			 @"cyan": [BeatColors colorWithRed:7 green:189 blue:235],
			 @"teal": [BeatColors colorWithRed:12 green:224 blue:227],
			 @"orange": [BeatColors colorWithRed:255 green:161 blue:13],
			 @"brown": [BeatColors colorWithRed:169 green:106 blue:7],
			 @"lightgray": [BeatColors colorWithRed:220 green:220 blue:220],
			 @"darkgray": [BeatColors colorWithRed:170 green:170 blue:170],
			 @"verydarkgray": [BeatColors colorWithRed:100 green:100 blue:100],
			 @"backgroundgray": [BeatColors colorWithRed:41 green:42 blue:45],
			 @"fdxremoval": [BeatColors colorWithRed:255 green:190 blue:220],
             @"mint": [BeatColors colorWithRed:72 green:231 blue:211],
             @"violet": [BeatColors colorWithRed:116 green:62 blue:230],
             @"olive": [BeatColors colorWithRed:77 green:147 blue:44],
	};
	
	return _colorValues;
}

+ (NSDictionary *)colors {
	BeatColors *colors = [self sharedColors];
	return colors.colorValues;
}
+ (BXColor *)colorWithRed: (CGFloat) red green:(CGFloat)green blue:(CGFloat)blue {
	#if TARGET_OS_IOS
		return [UIColor colorWithRed:(red / 255) green:(green / 255) blue:(blue / 255) alpha:1.0f];
	#else
		return [BXColor colorWithDeviceRed:(red / 255) green:(green / 255) blue:(blue / 255) alpha:1.0f];
	#endif
}
/*
+ (BeatColor*)randomColor {
	NSArray * colors = [BeatColors attributeKeys];
	NSUInteger index = arc4random_uniform((uint32_t)(colors.count - 1));
	return [BeatColors valueForKey:colors[index]];
}
 */

+ (BXColor*)color:(NSString*)name {
	BXColor* color = [BeatColors.colors valueForKey:name.lowercaseString];
	if (color) {
		return color;
	} else {
		NSString *hexColor = [NSString stringWithString:name];
		if (name.length == 7 && [name characterAtIndex:0] == '#') {
			hexColor = [hexColor substringFromIndex: 1];
			return [BeatColors colorWithHexColorString:hexColor];
		}
		
		return nil;
	}

}

// Thanks to Zlatan @ stackoverflow
+ (BXColor*)colorWithHexColorString:(NSString*)inColorString
{
	BXColor* result = nil;
    unsigned colorCode = 0;
    unsigned char redByte, greenByte, blueByte;

    if (nil != inColorString)
    {
         NSScanner* scanner = [NSScanner scannerWithString:inColorString];
         (void) [scanner scanHexInt:&colorCode]; // ignore error
    }
    redByte = (unsigned char)(colorCode >> 16);
    greenByte = (unsigned char)(colorCode >> 8);
    blueByte = (unsigned char)(colorCode); // masks off high bits

#if TARGET_OS_IOS
	result = [UIColor colorWithRed:(CGFloat)redByte / 0xff
							 green:(CGFloat)greenByte / 0xff
							  blue:(CGFloat)blueByte / 0xff
							 alpha:1.0];
#else
    result = [NSColor colorWithCalibratedRed:(CGFloat)redByte / 0xff
									   green:(CGFloat)greenByte / 0xff
										blue:(CGFloat)blueByte / 0xff
									   alpha:1.0];
#endif
    return result;
}

+ (NSString*)colorWith16bitHex:(NSString*)colorName {
	// Only use COLOR NAMES here
	BXColor *color = [self color:colorName];
	return [self get16bitHex:color];
	
}
+ (NSString*)get16bitHex:(BXColor *)color {
#if TARGET_OS_IOS
	CGFloat red; CGFloat green; CGFloat blue;
	[color getRed:&red green:&green blue:&blue alpha:nil];
#else
	CGFloat red = color.redComponent;
	CGFloat green = color.greenComponent;
	CGFloat blue = color.blueComponent;
#endif
	
	NSString* hexString = [NSString stringWithFormat:@"%04X%04X%04X",
						   (int) (red * 0xFFFF),
						   (int) (green * 0xFFFF),
						   (int) (blue * 0xFFFF)];
	return hexString;
}

+ (NSString*)cssRGBFor:(BXColor*)color
{
    NSString* result = @"";
#if TARGET_OS_OSX
    result = [NSString stringWithFormat:@"rgb(%f, %f, %f)", color.redComponent * 255, color.greenComponent * 255, color.blueComponent * 255];
#else
    CGFloat red; CGFloat green; CGFloat blue;
    [color getRed:&red green:&green blue:&blue alpha:nil];
    result = [NSString stringWithFormat:@"rgb(%f, %f, %f)", red * 255, green * 255, blue * 255];
#endif
    return result;
}

#if TARGET_OS_OSX

+ (BXImage*)labelImageForColor:(NSString*)colorName size:(CGSize)size
{
    BXColor* color = [BeatColors color:colorName.lowercaseString];
    return [BeatColors labelImageForColorValue:color size:size];
}

/// Creates an image to be used with UI elements to represent colors
+ (BXImage*)labelImageForColorValue:(BXColor*)color size:(CGSize)size
{
    static NSMutableDictionary<BXColor*, NSImage*>* labelImages;
    if (labelImages == nil) labelImages = NSMutableDictionary.new;
    
    if (labelImages[color] != nil) return labelImages[color];
    
    CGFloat w = size.width; CGFloat h = size.height;
    CGFloat padding = w * 0.1;
    
    NSImage* image = [NSImage.alloc initWithSize:CGSizeMake(w, h)];
    
    CGRect rect = CGRectMake(padding, padding, w - 2 * padding, h - 2 * padding);
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:w / 2 yRadius:h / 2];
    
    [image lockFocus];
    [color setFill];
    [path fill];
    [image unlockFocus];
    
    labelImages[color] = image;
    return image;
}

#else

+ (BXImage*)labelImageForColor:(NSString*)colorName size:(CGSize)size
{
    static NSMutableDictionary<NSString*, BXImage*>* labelImages;
    if (labelImages == nil) labelImages = NSMutableDictionary.new;
    
    colorName = colorName.lowercaseString;
    if (labelImages[colorName] != nil) return labelImages[colorName];
    
    BXColor* color = [BeatColors color:colorName];
    CGFloat w = size.width; CGFloat h = size.height;
    CGFloat padding = w * 0.1;
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), NO, 0.0);
    
    CGRect rect = CGRectMake(padding, padding, w - 2 * padding, h - 2 * padding);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:w / 2];
    
    [color setFill];
    [path fill];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    labelImages[colorName] = image;
    return image;
}

#endif

@end
/*
 
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 palavat runot valaisevat illan
 
 */
