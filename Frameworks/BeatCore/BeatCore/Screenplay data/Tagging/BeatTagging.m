//
//  BeatTagging.m
//  Beat
//
//  Created by Lauri-Matti Parppei on 6.2.2021.
//  Copyright © 2021 Lauri-Matti Parppei. All rights reserved.
//
/*
 
 Minimal tagging implementation. This relies on adding attributes into the BeatEditorView string,
 and tagging data is NOT present in the screenplay text. It is saved as a separate JSON string
 inside the document settings.
 
 We have two classes, BeatTag and TagDefinition (sorry for the inconsistence). BeatTags are
 added as attributes to the string (attribute name "BeatTag"), and they contain a reference
 to their definition. Definitions are created on the fly and get their text content from
 the first time something is tagged.
 
 This is similar to the Final Draft implementation, but for now, Beat doesn't allow
 choosing from a list of previous definitions or editing them directly.
 
 User tags a range in editor:
	-> editor presents a menu for existing items in the selected category
	-> add a reference to the tag definition as an attribute to the string
 
 Save document:
	-> create an array of tag definitions which are still present in the screenplay
	   (some might have been deleted)
    -> save tag ranges as previously, just include the tag definition reference

 Load document:
	-> load tag definitions using this class, create the aforementioned definition array
	-> load ranges and use this class to match tags to definitions
 
 Nice and easy, just needs some work.
 
 */

#import <BeatParsing/BeatParsing.h>
#import <BeatCore/BeatCore.h>
#import "BeatTagging.h"
#import "BeatTagItem.h"
#import "BeatTag.h"
#import "NSString+Levenshtein.h"
#import "BeatColors.h"

#define BXTagOrder @[ @"cast", @"prop", @"vfx", @"sfx", @"animal", @"extras", @"vehicle", @"costume", @"makeup", @"music" ]

#define UIFontSize 11.0

@implementation TagSearchResult
- (instancetype)initWith:(NSString*)string distance:(CGFloat)distance {
	self = [super init];
	self.distance = distance;
	self.string = string;
	return self;
}
@end

@interface BeatTagging ()
@property (nonatomic) NSMutableArray<TagDefinition*> *tagDefinitions;
@property (nonatomic) OutlineScene *lastScene;
@end

@implementation BeatTagging

+ (void)initialize {
	[super initialize];
	[BeatAttributes registerAttribute:BeatTagging.attributeKey];
}

- (instancetype)initWithDelegate:(id<BeatTaggingDelegate>)delegate {
	self = [super init];
	if (self) {
		self.delegate = delegate;
	}
	
	return self;
}

-(void)awakeFromNib {
    [super awakeFromNib];

}

- (void)setup {
	// Load tags from document settings
	[self loadTags:[_delegate.documentSettings get:DocSettingTags] definitions:[_delegate.documentSettings get:DocSettingTagDefinitions]];
}

+ (NSString*)attributeKey {
	return @"BeatTag";
}

+ (NSDictionary<NSNumber*,NSString*>*)tagKeys
{
    static NSDictionary* tagKeys;
    if (tagKeys == nil) tagKeys = @{
        @(CharacterTag): @"cast",
        @(PropTag): @"prop",
        @(VFXTag): @"vfx",
        @(SpecialEffectTag): @"sfx",
        @(AnimalTag): @"animal",
        @(ExtraTag): @"extras",
        @(VehicleTag): @"vehicle",
        @(CostumeTag): @"costume",
        @(MakeupTag): @"makeup",
        @(MusicTag): @"music"
    };
    
    return tagKeys;
}

+ (NSDictionary<NSNumber*, NSString*>*)tagIcons
{
    static NSDictionary* tagIcons;
    if (tagIcons == nil) tagIcons = @{
        @(CharacterTag): @"person.fill",
        @(PropTag): @"gym.bag.fill",
        @(VFXTag): @"fx",
        @(SpecialEffectTag): @"flame",
        @(AnimalTag): @"dog.fill",
        @(ExtraTag): @"person.3",
        @(VehicleTag): @"bicycle",
        @(CostumeTag): @"tshirt.fill",
        @(MakeupTag): @"theatermask.and.paintbrush.fill",
        @(MusicTag): @"music.note"
    };
    return tagIcons;
}

/// All available tag categories as string
+ (NSArray<NSString*>*)categories
{
    static NSArray* categories;
    if (categories == nil) categories = BXTagOrder;
    return categories;
}

+ (NSArray*)styledTags
{
	NSArray *tags = BeatTagging.categories;
    NSMutableArray *styledTags = NSMutableArray.new;
	
	// Add menu item to remove current tag
	[styledTags addObject:[[NSAttributedString alloc] initWithString:@"× None"]];
	
	for (NSString *tag in tags) {
		[styledTags addObject:[self styledTagFor:tag]];
	}
	
	return styledTags;
}

+ (NSString*)localizedTagNameOnType:(BeatTagType)type
{
    NSString* tag = [BeatTagging keyFor:type];
    return [BeatTagging localizedTagNameFor:tag];
}

+ (NSString*)localizedTagNameFor:(NSString*)tag
{
    return [BeatLocalization localizedStringForKey:[NSString stringWithFormat:@"tag.%@", tag]];
}

+ (NSAttributedString*)styledTagFor:(NSString*)tag
{
	TagColor *color = [(NSDictionary*)[BeatTagging tagColors] valueForKey:tag];
	
    NSString* localizedTag = [BeatLocalization localizedStringForKey:[NSString stringWithFormat:@"tag.%@", tag]];
    
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"● %@", localizedTag]];
	if (color) [string addAttribute:NSForegroundColorAttributeName value:color range:(NSRange){0, 1}];
	return string;
}

+ (NSAttributedString*)styledListTagFor:(NSString*)tag color:(TagColor*)textColor {
	TagColor *color = [(NSDictionary*)[BeatTagging tagColors] valueForKey:tag];
	
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.paragraphSpacing = 3.0;
	
	NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"● %@\n", tag]];
	if (color) [string addAttribute:NSForegroundColorAttributeName value:color range:(NSRange){0, 1}];
	[string addAttribute:NSForegroundColorAttributeName value:textColor range:(NSRange){1, string.length - 1}];
	[string addAttribute:NSFontAttributeName value:[TagFont boldSystemFontOfSize:UIFontSize] range:(NSRange){0, string.length}];
	[string addAttribute:NSParagraphStyleAttributeName value:paragraph range:(NSRange){0, string.length}];
	[string addAttribute:@"TagTitle" value:@"Yes" range:(NSRange){0, string.length - 1}];
	return string;
}

+ (NSDictionary*)tagColors
{
	return @{
		@"cast": [BeatColors color:@"cyan"],
		@"prop": [BeatColors color:@"orange"],
		@"costume": [BeatColors color:@"pink"],
		@"makeup": [BeatColors color:@"green"],
		@"vfx": [BeatColors color:@"purple"],
		@"animal": [BeatColors color:@"yellow"],
		@"extras": [BeatColors color:@"magenta"],
		@"vehicle": [BeatColors color:@"teal"],
		@"sfx": [BeatColors color:@"brown"],
		@"generic": [BeatColors color:@"gray"]
	};
}


+ (BeatTagType)tagFor:(NSString*)tag
{
	// Make the tag lowercase for absolute compatibility
	tag = tag.lowercaseString;
	if ([tag isEqualToString:@"cast"]) return CharacterTag;
	else if ([tag isEqualToString:@"prop"]) return PropTag;
	else if ([tag isEqualToString:@"vfx"]) return VFXTag;
	else if ([tag isEqualToString:@"sfx"]) return SpecialEffectTag;
	else if ([tag isEqualToString:@"animal"]) return AnimalTag;
	else if ([tag isEqualToString:@"extras"]) return ExtraTag;
	else if ([tag isEqualToString:@"vehicle"]) return VehicleTag;
	else if ([tag isEqualToString:@"costume"]) return CostumeTag;
	else if ([tag isEqualToString:@"makeup"]) return MakeupTag;
	else if ([tag isEqualToString:@"music"]) return MusicTag;
	else if ([tag isEqualToString:@"none"]) return NoTag;
	else { return GenericTag; }
}

+ (NSString*)keyFor:(BeatTagType)tag
{
    NSString* key = BeatTagging.tagKeys[@(tag)];
    return (key != nil) ? key : @"generic";
}

+ (TagColor*)colorFor:(BeatTagType)tag {
	NSDictionary *colors = [self tagColors];
	TagColor *color = [colors valueForKey:[self keyFor:tag]];
	if (!color) color = colors[@"generic"];
	
	return color;
}

+ (NSString*)hexForKey:(NSString*)key
{
	TagColor *color = [self tagColors][key];
	return [BeatColors get16bitHex:color];
}

+ (NSDictionary*)tagDictionary {
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	NSArray *tags = BeatTagging.categories;
	
	for (NSString* tag in tags) {
		[dict setValue:[NSMutableArray array] forKey:tag];
	}

	return dict;
}
+ (NSMutableDictionary*)tagDictionaryWithDictionaries {
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	NSArray *tags = BeatTagging.categories;
	
	for (NSString* tag in tags) {
		[dict setValue:[NSMutableDictionary dictionary] forKey:tag];
	}

	return dict;
}

- (void)loadTags:(NSArray<NSDictionary*>*)tags definitions:(NSArray*)definitions
{
	self.tagDefinitions = NSMutableArray.new;
	for (NSDictionary *dict in definitions) {
		TagDefinition *def = [[TagDefinition alloc] initWithName:dict[@"name"] type:[BeatTagging tagFor:dict[@"type"]] identifier:dict[@"id"]];
		[_tagDefinitions addObject:def];
	}
	
	for (NSDictionary* tag in tags) {
		NSArray *rangeValues = tag[@"range"];
		if (rangeValues.count < 2) continue; // Ignore faulty values
		
		NSInteger loc = [(NSNumber*)rangeValues[0] integerValue];
		NSInteger len = [(NSNumber*)rangeValues[1] integerValue];
		
		NSRange range = (NSRange){ loc, len };
		
		TagDefinition *def = [self definitionForId:tag[@"definition"]];
		BeatTag *newTag = [BeatTag withDefinition:def];
		
		if (range.length > 0) {
			[self tagRange:range withTag:newTag];
		}
	}
}

/**
 This bakes the tag items in text view string into given set of lines. The lines then retain the references to the tag items, which we carry on to FDX export. It's a class method for some reason.
 */
+ (void)bakeAllTagsInString:(NSAttributedString*)textViewString toLines:(NSArray*)lines
{
	for (Line *line in lines) {
		if (line.length == 0) continue;
		
        line.tags = NSMutableArray.new;

		// Local string from the attributed content using line range
		if (line.range.location >= textViewString.length) break;
		NSAttributedString *string = [textViewString attributedSubstringFromRange:line.textRange];
		
		// Enumerate through tags in the attributed string		
		[string enumerateAttribute:BeatTagging.attributeKey inRange:(NSRange){0, line.string.length} options:0 usingBlock:^(id _Nullable value, NSRange range, BOOL * _Nonnull stop) {
			BeatTag *tag = (BeatTag*)value;
			
			if (!tag || range.length == 0) return;
						
			[line.tags addObject:@{
				@"tag": tag,
				@"range": [NSValue valueWithRange:range]
			}];
		}];
	}
}

- (NSArray*)allTags {
	NSMutableArray *tags = [NSMutableArray array];
    NSAttributedString *string = _delegate.attributedString;
	
	[string enumerateAttribute:BeatTagging.attributeKey inRange:(NSRange){0, string.length} options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
		BeatTag *tag = (BeatTag*)value;
		if (tag.type == NoTag) return; // Just in case
		
		// Save current range of the tag into the object and add to array
		tag.range = range;
		[tags addObject:tag];
	}];
	
	return tags;
}

- (NSArray<TagDefinition*>*)tagsWithTypeName:(NSString*)type
{
    NSMutableArray<TagDefinition*>* tags = NSMutableArray.new;
    NSAttributedString *string = _delegate.attributedString;
    
    [string enumerateAttribute:BeatTagging.attributeKey inRange:NSMakeRange(0, string.length) options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
        BeatTag *tag = (BeatTag*)value;
        
        if (![tag.key isEqualToString:type] || tag.definition == nil) return;
        if (![tags containsObject:tag.definition]) [tags addObject:tag.definition];
    }];
    
    return tags;
}

- (NSDictionary<NSString*, NSArray<TagDefinition*>*>*)sortedTags
{
    return [self sortedTagsInRange:NSMakeRange(0, self.delegate.text.length)];
}

- (NSDictionary<NSString*, NSArray<TagDefinition*>*>*)sortedTagsInRange:(NSRange)searchRange
{
    NSArray* lines = [self.delegate.parser linesInRange:searchRange];
    
	NSDictionary *tags = [BeatTagging tagDictionary];
    NSAttributedString *string = _delegate.attributedString;
	
	[string enumerateAttribute:BeatTagging.attributeKey inRange:searchRange options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
		BeatTag *tag = (BeatTag*)value;
		
		if (tag.type == NoTag) return;
		tag.range = range;
		
		// Add definition to array if it's not present yet
		if (tag.definition) {
			NSMutableArray *tagDefinitions = tags[tag.key];
			if (![tagDefinitions containsObject:tag.definition]) [tagDefinitions addObject:tag.definition];
		}
	}];
    
    for (Line* line in lines) {
        if (!line.isAnyCharacter) continue;
        
        NSString* characterName = line.characterName.uppercaseString;
        BeatTag* tag = [self addTag:characterName type:CharacterTag];
        if (![tags[@"cast"] containsObject:tag.definition]) [tags[@"cast"] addObject:tag.definition];
    }
    
	return tags;
}

- (NSArray<TagDefinition*>*)tagsInRange:(NSRange)searchRange {
    NSArray* lines = [self.delegate.parser linesInRange:searchRange];
    
    NSMutableArray<TagDefinition*>* tags = NSMutableArray.new;
    NSAttributedString *string = _delegate.attributedString;
    
    [string enumerateAttribute:BeatTagging.attributeKey inRange:searchRange options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
        BeatTag *tag = (BeatTag*)value;
        
        if (tag.type == NoTag) return;
        tag.range = range;
        
        // Add definition to array if it's not present yet
        if (tag.definition) {
            if (![tags containsObject:tag.definition]) [tags addObject:tag.definition];
        }
    }];
    
    for (Line* line in lines) {
        if (!line.isAnyCharacter) continue;
        
        NSString* characterName = line.characterName.uppercaseString;
        BeatTag* tag = [self addTag:characterName type:CharacterTag];
        if (![tags containsObject:tag.definition]) [tags addObject:tag.definition];
    }
    
    return tags;
}

- (NSDictionary*)tagsForScene:(OutlineScene*)scene
{
	[self.delegate.parser updateOutline];
    return [self sortedTagsInRange:scene.range];
}

- (NSArray<OutlineScene*>*)scenesForTagDefinition:(TagDefinition*)tag
{
    NSMutableArray<OutlineScene*>* scenes = NSMutableArray.new;
    
    for (OutlineScene* scene in self.delegate.parser.scenes) {
        NSArray* tags = [self tagsInRange:scene.range];
        if ([tags containsObject:tag]) [scenes addObject:scene];
    }
    
    return scenes;
}

- (NSDictionary*)tagsByType {
	// This could be used to attach tags to corresponding IDs
	NSDictionary *tags = [BeatTagging tagDictionary];
	
	for (OutlineScene *scene in _delegate.parser.scenes) {
		NSDictionary *sceneTags = [self tagsForScene:scene];
		
		for (NSString *key in sceneTags.allKeys) {
			NSArray *taggedItems = sceneTags[key];
			NSMutableArray *allItems = tags[key];
			
			for (TagDefinition *item in taggedItems) {
				if (![allItems containsObject:item]) [allItems addObject:item];
			}
		}
	}
	
	return tags;
}

- (void)bakeTags {
    NSAttributedString *string = _delegate.attributedString;
	[BeatTagging bakeAllTagsInString:string toLines:self.delegate.parser.lines];
}

#pragma mark - UI methods for displaying tags in editor

- (NSAttributedString*)displayTagsForScene:(OutlineScene*)scene {
	if (!scene) return [[NSAttributedString alloc] initWithString:@""];
	
	NSMutableDictionary *tags = [NSMutableDictionary dictionaryWithDictionary:[self tagsForScene:scene]];
	NSMutableAttributedString *result = NSMutableAttributedString.new;
	
	[result appendAttributedString:[self boldedString:scene.stringForDisplay.uppercaseString color:nil]];
	[result appendAttributedString:[self str:@"\n\n"]];
	
	NSInteger headingLength = result.length;
	 
	// Get location
	NSString *location = scene.stringForDisplay;
	Rx *rx = [Rx rx:@"^(int|ext)" options:NSRegularExpressionCaseInsensitive];
	if ([location isMatch:rx]) {
		NSRange preRange = [location rangeOfString:@" "];
		location = [location substringFromIndex:preRange.location];
	}
	if ([location rangeOfString:@" - "].location != NSNotFound) {
		location = [location substringWithRange:(NSRange){0, [location rangeOfString:@" - "].location}];
	}
	location = [location stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	
	[result appendAttributedString:[self boldedString:@"Location\n" color:nil]];
	[result appendAttributedString:[self str:location]];
	[result appendAttributedString:[self str:@"\n\n"]];
	
	// List cast first
	NSArray *cast = tags[@"Cast"];
	if (cast.count) {
		[result appendAttributedString:[BeatTagging styledListTagFor:@"Cast" color:TagColor.whiteColor]];
		
		for (TagDefinition *tag in cast) {
			[result appendAttributedString:[self str:tag.name]];
			[result appendAttributedString:[self str:@"\n"]];
			if (cast.lastObject == tag) [result appendAttributedString:[self str:@"\n"]];
		}

		tags[@"Cast"] = nil; // Reset so we don't iterate over it again later
	}
	
	for (NSString* tagKey in tags.allKeys) {
		NSArray *items = tags[tagKey];
		if (items.count) {
			[result appendAttributedString:[BeatTagging styledListTagFor:tagKey color:TagColor.whiteColor]];
			
			for (TagDefinition *tag in items) {
				[result appendAttributedString:[self str:tag.name]];
				[result appendAttributedString:[self str:@"\n"]];
				
				if (items.lastObject == tag) [result appendAttributedString:[self str:@"\n"]];
			}
		}
	}
	
	if (result.length == headingLength) {
		[result appendAttributedString:[self string:@"No tagging data. Select a range in the screenplay to start tagging." withColor:TagColor.systemGrayColor]];
	}
	
	return result;
}

// String helpers
- (NSAttributedString*)str:(NSString*)string {
	return [self string:string withColor:TagColor.whiteColor];
}
- (NSAttributedString*)string:(NSString*)string withColor:(TagColor*)color {
	if (!color) color = TagColor.whiteColor;
	return [[NSAttributedString alloc] initWithString:string attributes:@{ NSFontAttributeName: [TagFont systemFontOfSize:UIFontSize], NSForegroundColorAttributeName: color }];
}
- (NSAttributedString*)boldedString:(NSString*)string color:(TagColor*)color {
	if (!color) color = TagColor.whiteColor;
	return [[NSAttributedString alloc] initWithString:string attributes:@{ NSFontAttributeName: [TagFont boldSystemFontOfSize:UIFontSize], NSForegroundColorAttributeName: color }];
}

#pragma mark - Actual tagging

- (BeatTag*)addTag:(NSString*)name type:(BeatTagType)type {
	if (type == NoTag) return nil;
	
	TagDefinition *def = [self searchForTag:name type:type];
	
	if (!def) return [self newTag:name type:type];
	else return [self newTagWithDefinition:def];
}

- (BeatTag*)newTag:(NSString*)name type:(BeatTagType)type {
	name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	if (type == CharacterTag) name = name.uppercaseString;
	
	TagDefinition *def = [[TagDefinition alloc] initWithName:name type:type identifier:[BeatTagging newId]];
	[_tagDefinitions addObject:def];
	
	return [BeatTag withDefinition:def];
}

- (BeatTag*)newTagWithDefinition:(TagDefinition*)def {
	return [BeatTag withDefinition:def];
}

- (TagDefinition*)definitionWithName:(NSString*)name type:(BeatTagType)type {
	for (TagDefinition* def in self.tagDefinitions) {
		if (def.type != type) continue;
		if ([def.name isEqualToString:name]) return def;
	}
	return nil;
}

+ (NSString*)newId {
	NSUUID *uuid = [NSUUID UUID];
	return [uuid UUIDString].lowercaseString;
}

- (TagDefinition*)searchForTag:(NSString*)string type:(BeatTagType)type
{
	string = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	
	for (TagDefinition *tag in _tagDefinitions) {
		if (tag.type == type && [tag.name.lowercaseString isEqualToString:string.lowercaseString]) return tag;
	}
	
	return nil;
}

/// Returns an array of tags that fit both the search string and type. It uses Levenshtein algorithm, so results include things that *somehow* contain the string.
- (NSArray<TagDefinition*>*)searchTagsByTerm:(NSString*)string type:(BeatTagType)type
{
	NSMutableArray *matches = [NSMutableArray array];
	
	string = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	
	for (TagDefinition *tag in _tagDefinitions) {
		// Ignore stuff that isn't this type
		if (tag.type != type) continue;
		
		// Calculate Levenshtein distance
		CGFloat distance = [string compareWithString:tag.name];
		TagSearchResult *result = [TagSearchResult.alloc initWith:tag.name distance:distance];
		[matches addObject:result];
	}
	
	// Sort results using Levenshtein algorithm
	if (matches.count) [matches sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"distance" ascending:YES]]];
	
	// Convert results to strings
	NSMutableArray *matchStrings = NSMutableArray.array;
	for (TagSearchResult *result in matches) {
		[matchStrings addObject:result.string];
	}
	
	return matchStrings;
}

- (bool)tagExists:(NSString*)string type:(BeatTagType)type
{
    return ([self searchForTag:string type:type] != nil);
}

/// Returns an array for saving the tags as JSON. This is a misleading name and should be fixed.
- (NSArray*)getTags
{
    NSMutableArray *tagsToSave = NSMutableArray.new;
    NSArray *tags = [self allTags];
    
    for (BeatTag* tag in tags) {
        [tagsToSave addObject:@{
            @"range": @[ @(tag.range.location), @(tag.range.length) ],
            @"type": tag.key,
            @"definition": tag.defId
        }];
    }
    
    return tagsToSave;
}

/// Returns dictionary values for used definitions
- (NSArray*)getDefinitions
{
	NSArray *allTags = [self allTags];
	NSMutableArray *defs = [NSMutableArray array];
	
	for (BeatTag* tag in allTags) {
		if (![defs containsObject:tag.definition]) [defs addObject:tag.definition];
	}
	
	NSMutableArray *defsToSave = [NSMutableArray array];
	for (TagDefinition *def in defs) {
		[defsToSave addObject:@{
			@"name": def.name,
			@"type": [BeatTagging keyFor:def.type],
			@"id": def.defId
		}];
	}
	
	return defsToSave;
}
+ (NSMutableArray<TagDefinition*>*)definitionsForTags:(NSArray<BeatTag*>*)tags
{
    NSMutableArray<TagDefinition*>* defs = NSMutableArray.new;
	
	for (BeatTag *tag in tags) {
		if (![defs containsObject:tag.definition]) [defs addObject:tag.definition];
	}
	
	return defs;
}

- (NSArray*)definitionsForKey:(NSString*)key {
	NSMutableArray *tags = [NSMutableArray array];
	BeatTagType type = [BeatTagging tagFor:key];
	
	for (TagDefinition *def in _tagDefinitions) {
		if (def.type == type) [tags addObject:def];
	}
	
	return tags;
}

- (BeatTagType)typeForId:(NSString*)defId {
	for (TagDefinition *def in _tagDefinitions) {
		if ([def hasId:defId]) return def.type;
	}
	return NoTag;
}

- (TagDefinition*)definitionFor:(BeatTag*)tag {
	return [self definitionForId:tag.defId];
}

- (TagDefinition*)definitionForId:(NSString*)defId {
	for (TagDefinition *def in _tagDefinitions) {
		if ([def.defId isEqualToString:defId]) return def;
	}
	return nil;
}

/*
// Alternate code
#pragma mark - Saving into Fountain file

- (NSDictionary*)tagsForSaving {
	NSArray *tags = self.allTags;
	
	NSMutableDictionary <NSString*, NSMutableArray*>*tagDict = NSMutableDictionary.new;
	NSMutableArray *definitions = NSMutableArray.new;
	NSMutableDictionary <NSValue*, NSString*> *ranges = NSMutableDictionary.new;
	
	for (BeatTag *tag in tags) {
		if (tag.definition) {
			if (!tagDict[tag.key]) tagDict[tag.key] = NSMutableArray.new;
			
			// Save a JSON-compatible dictionary into definition array
			NSMutableArray *tagDefinitions = tagDict[tag.key];
			if (![tagDefinitions containsObject:tag.definition]) [tagDefinitions addObject:tag.definition.serialized];
			
			// Save range + ID for the definition
			NSValue *r = [NSValue valueWithRange:tag.range];
			NSValue *rangeKey = [NSValue valueWithNonretainedObject:r];
			ranges[rangeKey] = tag.definition.defId;
		}
		
	}
	
	return @{
		@"definitions": definitions,
		@"taggedRanges": ranges
	};
}
 */

#pragma mark - Editor methods

- (void)tagRange:(NSRange)range withType:(BeatTagType)type {
	NSString *string = [self.delegate.text substringWithRange:range];
	BeatTag* tag = [self addTag:string type:type];
	
	if (tag) {
		[self tagRange:range withTag:tag];
		[self.delegate.formatting forceFormatChangesInRange:range];
	}
}

- (void)tagRange:(NSRange)range withDefinition:(id)definition {
	TagDefinition *def = (TagDefinition*)definition;
	BeatTag *tag = [BeatTag withDefinition:def];

	[self tagRange:range withTag:tag];
	[self.delegate.formatting forceFormatChangesInRange:range];
}

- (void)tagRange:(NSRange)range withTag:(BeatTag*)tag {
	// Tag a range with the specified tag.
	// NOTE that this just sets attribute ranges and doesn't save the tag data anywhere else.
	// So the tagging system basically only relies on the attributes in the NSTextView's rich-text string.
	
	//NSDictionary *oldAttributes = [self.delegate.attributedString attributesAtIndex:range.location longestEffectiveRange:nil inRange:range];
    NSAttributedString* oldAttributedString = self.delegate.attributedString;
	
	if (tag == nil) {
		// Clear tags
		[_delegate.textStorage removeAttribute:BeatTagging.attributeKey range:range];
		[self saveTags];
	} else {
		[_delegate.textStorage addAttribute:BeatTagging.attributeKey value:tag range:range];
		[self saveTags];
	}
	
	if (_delegate.documentIsLoading) return;
	
	
	// If document is not loading, set undo states
    // TODO: Save previous attributes (see how parts of undoing work in revision manager)
	
	[self.delegate.undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		NSLog(@"# NOTE: Test this before making tagging public.");
		[self.delegate.textStorage removeAttribute:BeatTagging.attributeKey range:range];
		[oldAttributedString enumerateAttribute:BeatTagging.attributeKey inRange:range options:0 usingBlock:^(id  _Nullable value, NSRange tRange, BOOL * _Nonnull stop) {
			if (value == nil) return;
			
			[self.delegate.textStorage addAttribute:BeatTagging.attributeKey value:value range:tRange];
		}];
	}];
	
}

- (void)saveTags
{
	NSArray *tags = [self getTags];
	NSArray *definitions = [self getDefinitions];
	
	[_delegate.documentSettings set:DocSettingTags as:tags];
	[_delegate.documentSettings set:DocSettingTagDefinitions as:definitions];
}

- (void)updateTaggingData 
{
    NSAttributedString* tagInfo = [self displayTagsForScene:self.delegate.currentScene];
    [self.tagTextView.textStorage setAttributedString:tagInfo];
}



#pragma mark - Editor actions

- (IBAction)toggleTagging:(id)sender {
	[_delegate toggleMode:TaggingMode];
}

- (IBAction)closeTagging:(id)sender {
    [_delegate toggleMode:EditMode];
}

@end
