//
//  BeatDocumentBaseController.m
//  BeatCore
//
//  Created by Lauri-Matti Parppei on 7.11.2023.
//

#import "BeatDocumentBaseController.h"
#import <BeatCore/BeatCore-Swift.h>
#import <BeatCore/BeatTextIO.h>
#import <BeatCore/BeatRevisions.h>
#import <BeatCore/BeatCompatibility.h>
#import <BeatCore/NSTextView+UX.h>
#import <BeatCore/BeatEditorFormatting.h>
#import <BeatCore/BeatUserDefaults.h>
#import <BeatCore/BeatLayoutManager.h>
#import <BeatCore/BeatFonts.h>

#define FORWARD_TO( CLASS, TYPE, METHOD ) \
- (TYPE)METHOD { [CLASS METHOD]; }

@interface BeatDocumentBaseController()

@end

@implementation BeatDocumentBaseController


#pragma mark - Identity

#if TARGET_OS_OSX
- (id)document
{
    return self;
}
#endif

- (NSUUID*)uuid
{
    if (_uuid == nil) _uuid = NSUUID.new;
    return _uuid;
}


#pragma mark - Setting getters and setters

- (bool)showRevisedTextColor
{
    return [BeatUserDefaults.sharedDefaults getBool:BeatSettingShowRevisedTextColor];
}

- (bool)printSceneNumbers
{
    return [BeatUserDefaults.sharedDefaults getBool:@"printSceneNumbers"];
}

- (void)setPrintSceneNumbers:(bool)value
{
    [BeatUserDefaults.sharedDefaults saveBool:value forKey:@"printSceneNumbers"];
}


#pragma mark - Editor styles

- (BeatStylesheet *)editorStyles
{
    BeatStylesheet* styles = [BeatStyles.shared editorStylesFor:[self.documentSettings getString:DocSettingStylesheet]];
    return (styles != nil) ? styles : BeatStyles.shared.defaultEditorStyles;
}
- (BeatStylesheet *)styles
{
    BeatStylesheet* styles = [BeatStyles.shared stylesFor:[self.documentSettings getString:DocSettingStylesheet]];
    return (styles != nil) ? styles : BeatStyles.shared.defaultStyles;
}

/// Reloads all styles
- (void)reloadStyles
{
    [self.styles reload];
    [self.editorStyles reload];
    [self resetPreview];
    // NOTE: This has to be called in OS-specific implementation as well.
}

/// Returns __actual__ line height for editor view
- (CGFloat)editorLineHeight
{
    return self.editorStyles.page.lineHeight;
}

/// Returns LINE HEIGHT MODIFIER (!!!), not actual line height
- (CGFloat)lineHeight
{
    return self.editorStyles.page.lineHeight / 12.0;
}

- (void)ensureLayout
{
    NSLog(@"ensureLayout should be overridden by the OS-specific class.");
}


#pragma mark - Document setting shorthands

#pragma mark Page size

/// Returns the current page size, or default size if none is applied
- (BeatPaperSize)pageSize
{
    if ([self.documentSettings has:DocSettingPageSize]) {
        return [self.documentSettings getInt:DocSettingPageSize];
    } else {
        return [BeatUserDefaults.sharedDefaults getInteger:@"defaultPageSize"];
    }
}

/// Remember to override/supplement this in OS-specific implementations to correctly set view size
- (void)setPageSize:(BeatPaperSize)pageSize
{
    [self.documentSettings setInt:DocSettingPageSize as:pageSize];
}

#pragma mark Scene numbering

- (NSInteger)sceneNumberingStartsFrom
{
    return [self.documentSettings getInt:DocSettingSceneNumberStart];
}
- (void)setSceneNumberingStartsFrom:(NSInteger)number {
    [self.documentSettings setInt:DocSettingSceneNumberStart as:number];
}

#pragma mark Export settings

-(BeatExportSettings*)exportSettings
{
    BeatExportSettings* settings = [BeatExportSettings operation:ForPreview delegate:(id<BeatExportSettingDelegate>)self];
    return settings;
}



#pragma mark - Line lookup

- (Line*)currentLine
{
    _previouslySelectedLine = _currentLine;
    
    NSInteger location = self.selectedRange.location;
    
    if (location >= self.text.length) {
        // Check if we're on the last line
        return self.parser.lines.lastObject;
    } else if (NSLocationInRange(location, _currentLine.range) && _currentLine != nil) {
        // Don't fetch the line if we already know it
        return _currentLine;
    } else {
        // Otherwise get the line and store it
        Line *line = [self.parser lineAtPosition:location];
        _currentLine = line;
        return _currentLine;
    }
}


#pragma mark - Scene lookup

- (OutlineScene*)currentScene
{
    // If we are not on the main thread, return the latest known scene
    if (!NSThread.isMainThread) return _currentScene;
    
    OutlineScene* scene = [self getCurrentSceneWithPosition:self.selectedRange.location];
    _currentScene = scene;
    return scene;
}

- (OutlineScene*)getCurrentSceneWithPosition:(NSInteger)position
{
    NSArray* outline = self.parser.safeOutline;
    // If the position is inside the stored current scene, just return that.
    if (_currentScene && NSLocationInRange(position, _currentScene.range) && [outline containsObject:_currentScene]) {
        return _currentScene;
    }
    
    // At the end, return last scene
    if (position >= self.text.length) return outline.lastObject;
    
    OutlineScene *prevScene;
    for (OutlineScene *scene in outline) {
        if (NSLocationInRange(position, scene.range))  {
            return scene;
        } else if (position >= NSMaxRange(prevScene.range) && position < scene.position && prevScene) {
            return prevScene;
        }
        
        prevScene = scene;
    }
    
    return nil;
}

- (OutlineScene*)getPreviousScene
{
    NSArray *outline = self.parser.safeOutline;
    if (outline.count == 0) return nil;
    
    NSInteger lineIndex = [self.parser indexOfLine:self.currentLine] ;
    if (lineIndex == NSNotFound || lineIndex >= self.parser.lines.count - 1) return nil;
    
    for (NSInteger i = lineIndex - 1; i >= 0; i--) {
        Line* line = self.parser.lines[i];
        
        if (line.type == heading || line.type == section) {
            for (OutlineScene *scene in outline) {
                if (scene.line == line) return scene;
            }
        }
    }
    
    return nil;
}
- (OutlineScene*)getNextScene
{
    NSArray *outline = self.parser.safeOutline;
    if (outline.count == 0) return nil;
    
    NSInteger lineIndex = [self.parser indexOfLine:self.currentLine] ;
    if (lineIndex == NSNotFound || lineIndex >= self.parser.lines.count - 1) return nil;
    
    for (NSInteger i = lineIndex + 1; i < self.parser.lines.count; i++) {
        Line* line = self.parser.lines[i];
        
        if (line.type == heading || line.type == section) {
            for (OutlineScene *scene in outline) {
                if (scene.line == line) return scene;
            }
        }
    }
    
    return nil;
}


#pragma mark - Formatting

// A collection of shorthands for delegation

- (void)formatLine:(Line*)line
{
    [_formatting formatLine:line];
}

- (void)formatAllLines
{
    for (Line* line in self.parser.lines) {
        @autoreleasepool { [_formatting formatLine:line]; }
    }
    
    [self.parser.changedIndices removeAllIndexes];
    [self ensureLayout];
}

- (IBAction)reformatEverything:(id)sender
{
    [self.parser resetParsing];
    [self applyFormatChanges];
    [self formatAllLines];
}

/// When something was changed, this method takes care of reformatting every line
- (void)applyFormatChanges
{
    [self.parser.changedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx >= _parser.lines.count) { *stop = true; return; }
        [_formatting formatLine:self.parser.lines[idx]];
    }];
    
    [self.parser.changedIndices removeAllIndexes];
}

/// Forces reformatting of a range
- (void)forceFormatChangesInRange:(NSRange)range
{
    #if TARGET_OS_OSX
        [self.textView.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:NSColor.clearColor forCharacterRange:range];
    #endif
    
    NSArray *lines = [self.parser linesInRange:range];
    for (Line* line in lines) {
        [_formatting formatLine:line];
    }
}

- (void)reformatLinesAtIndices:(NSMutableIndexSet *)indices
{
    [indices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        NSMutableString *str = [NSMutableString string];
        
        Line *line = self.parser.lines[idx];
        
        [line.noteRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
            [str appendString:[line.string substringWithRange:range]];
        }];
        
        [_formatting formatLine:line];
    }];
}

- (void)renderBackgroundForRange:(NSRange)range {
    NSArray *lines = [self.parser linesInRange:range];
    for (Line* line in lines) {
        // Invalidate layout
        [self.formatting refreshRevisionTextColorsInRange:line.textRange];
        [self.layoutManager invalidateDisplayForCharacterRange:line.textRange];
    }
}

- (void)renderBackgroundForLine:(Line*)line clearFirst:(bool)clear
{
    // Invalidate layout
    [self.layoutManager invalidateDisplayForCharacterRange:line.textRange];
}

/// Forces a type on a line and formats it accordingly. Can be abused for doing strange and esoteric stuff.
- (void)setTypeAndFormat:(Line*)line type:(LineType)type
{
    line.type = type;
    [self formatLine:line];
}

- (void)renderBackgroundForLines
{
    for (Line* line in self.lines) {
        // Invalidate layout
        [self.formatting refreshRevisionTextColorsInRange:line.textRange];
        [self.layoutManager invalidateDisplayForCharacterRange:line.textRange];
    }
}



#pragma mark - Parser shorthands

- (NSMutableArray<Line*>* _Nonnull)lines
{
    return _parser.lines;
}

- (NSArray<OutlineScene*>*)outline
{
    if (self.parser.outline == nil) return @[];
    else return self.parser.outline.copy;
}


#pragma mark - Preview creation
/// - note: The base class has no knowledge of OS-specific implementation of the preview controller.

- (void)createPreviewAt:(NSRange)range
{
    [self.previewController createPreviewWithChangedRange:range sync:false];
}

- (void)createPreviewAt:(NSRange)range sync:(BOOL)sync
{
    [self.previewController createPreviewWithChangedRange:range sync:sync];
}

- (void)invalidatePreview
{
    [self.previewController resetPreview];
}

- (void)invalidatePreviewAt:(NSInteger)index
{
    [self.previewController invalidatePreviewAt:NSMakeRange(index, 0)];
}

- (void)resetPreview
{
    [self.previewController resetPreview];
}


#pragma mark - Pagination

/// Returns the current pagination in preview controller
/// - note: Required to conform to plugin API.
- (BeatPaginationManager*)pagination { return self.previewController.getPagination; }
- (BeatPaginationManager*)paginator { return self.previewController.getPagination; }

/// Paginates this document from scratch
- (void)paginate
{
    [self paginateAt:(NSRange){0,0} sync:NO];
}

- (void)paginateAt:(NSRange)range sync:(bool)sync
{
    // Don't paginate while loading
    if (!self.documentIsLoading) [self.previewController createPreviewWithChangedRange:range sync:sync];
}

/// Pagination finished — called when preview controller has finished creating pagination
- (void)paginationFinished:(BeatPagination * _Nonnull)operation indices:(NSIndexSet * _Nonnull)indices pageBreaks:(NSDictionary<NSValue *,NSArray<NSNumber *> *> * _Nonnull)pageBreaks
{
    __block NSIndexSet* changedIndices = indices.copy;
    
    // We might be in a background thread, so make sure to dispach this call to main thread
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        // Update pagination in text view
        BeatLayoutManager* lm = (BeatLayoutManager*)self.getTextView.layoutManager;
        lm.pageBreaks = pageBreaks;

        #if TARGET_OS_OSX
            self.textView.needsDisplay = true;
        #else
            [self.textView setNeedsDisplay];
        #endif

        // Tell plugins the preview has been finished
        for (id<BeatPluginInstance> plugin in self.runningPlugins.allValues) {
            [plugin previewDidFinish:operation indices:changedIndices];
        }
    });
}

/*
Cycle inside Beat AppStore; building could produce unreliable results.
Cycle details:
→ Target 'Beat AppStore' has copy command from '/Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Products/Debug/BeatCore.framework' to '/Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Products/Debug/Beat.app/Contents/Frameworks/BeatCore.framework'
○ Target 'Beat AppStore' has compile command with input '/Users/lmp/Koodaus/Beat/Beat/User Interface/About Screen/BeatAboutScreen.m'
○ Target 'Beat AppStore' has Swift tasks blocking downstream compilation
○ Target 'Beat AppStore': SwiftMergeGeneratedHeaders /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/DerivedSources/Beat-Swift.h /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/Objects-normal/x86_64/Beat-Swift.h
○ Target 'Beat AppStore' has Swift tasks blocking downstream compilation


Raw dependency cycle trace:

target:  ->

node: <all> ->

command: <all> ->

node: /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Products/Debug/Beat.app/Contents/Frameworks/BeatCore.framework/Versions/A ->

command: P0:target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea-:Debug:Copy /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Products/Debug/Beat.app/Contents/Frameworks/BeatCore.framework /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Products/Debug/BeatCore.framework ->

node: <target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea--fused-phase0-compile-sources&link-binary&copy-bundle-resources> ->

command: P2:::Gate target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea--fused-phase0-compile-sources&link-binary&copy-bundle-resources ->

node: /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/Objects-normal/x86_64/BeatAboutScreen.o ->

command: P0:target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea-:Debug:CompileC /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/Objects-normal/x86_64/BeatAboutScreen.o /Users/lmp/Koodaus/Beat/Beat/User Interface/About Screen/BeatAboutScreen.m normal x86_64 objective-c com.apple.compilers.llvm.clang.1_0.compiler ->

node: <target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea--swift-generated-headers> ->

command: P2:::Gate target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea--swift-generated-headers ->

node: /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/Objects-normal/x86_64/Beat AppStore Swift Compilation Requirements Finished ->

CYCLE POINT ->

command: P1:target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea-:Debug:SwiftDriver Compilation Requirements Beat AppStore normal x86_64 com.apple.xcode.tools.swift.compiler ->

node: /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/DerivedSources/Beat-Swift.h ->

command: P1:target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea-:Debug:SwiftMergeGeneratedHeaders /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/DerivedSources/Beat-Swift.h /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/Objects-normal/x86_64/Beat-Swift.h ->

node: /Users/lmp/Library/Developer/Xcode/DerivedData/Beat-buyqzklaxxwnikcorbfamrjcqqyx/Build/Intermediates.noindex/Beat macOS.build/Debug/Beat AppStore.build/Objects-normal/x86_64/Beat-Swift.h ->

command: P1:target-Beat AppStore-a2a2f4cc340fe59da29ee8f8f2a683fc5b6859b7e8bf4ca37f8a06ffbd7760ea-:Debug:SwiftDriver Compilation Requirements Beat AppStore normal x86_64 com.apple.xcode.tools.swift.compiler


 */

#pragma mark - Text view components

- (BXTextView*)getTextView { return self.textView; }
- (NSTextStorage*)textStorage { return self.textView.textStorage; }
- (NSLayoutManager*)layoutManager { return self.textView.layoutManager; }

- (void)refreshTextView
{
    // Fuck you Apple for this:
    #if TARGET_OS_OSX
        [self.textView setNeedsDisplay:true];
    #else
        [self.textView setNeedsDisplay];
    #endif
}


#pragma mark - Misc stuff

-(NSString *)displayName
{
    NSLog(@"Override displayName in OS-specific implementation");
    return nil;
}


#pragma mark - Selection

- (NSRange)selectedRange {
    return self.textView.selectedRange;
}
- (void)setSelectedRange:(NSRange)range {
    [self setSelectedRange:range withoutTriggeringChangedEvent:NO];
}
/// Set selected range but DO NOT trigger the didChangeSelection: event
- (void)setSelectedRange:(NSRange)range withoutTriggeringChangedEvent:(bool)triggerChangedEvent {
    _skipSelectionChangeEvent = triggerChangedEvent;
    
    @try {
        [self.textView setSelectedRange:range];
    }
    @catch (NSException *e) {
        NSLog(@"Selection out of range");
    }
}

- (bool)caretAtEnd {
#if TARGET_OS_OSX
    return (self.textView.selectedRange.location == self.textView.string.length);
#else
    return (self.textView.selectedRange.location == self.textView.text.length);
#endif
}



#pragma mark - Text getter/setter

- (NSString *)text {
    if (!NSThread.isMainThread) return self.attrTextCache.string;
    return self.textView.text;
}

- (void)setText:(NSString *)text
{
    if (!self.textView) {
        // View is not ready yet, set text to buffer
        self.contentBuffer = text;
    } else {
        // Set text on screen
        [self.textView setText:text];
    }
}

#pragma mark - Text cache

- (NSAttributedString *)getAttributedText
{
    NSAttributedString* attrStr;
    if (!NSThread.isMainThread) attrStr = self.attrTextCache;
    else attrStr = self.textView.textStorage;
    
    return (attrStr != nil) ? attrStr : NSAttributedString.new;
}

- (NSAttributedString*)attributedString
{
    return [self getAttributedText];
}


#pragma mark - Text actions

// Because of some legacy stuff, text I/O methods are forwarded from this class to BeatTextIO.

FORWARD_TO(self.textActions, void, replaceCharactersInRange:(NSRange)range withString:(NSString*)string);
FORWARD_TO(self.textActions, void, addString:(NSString*)string atIndex:(NSUInteger)index);
FORWARD_TO(self.textActions, void, addString:(NSString*)string atIndex:(NSUInteger)index skipAutomaticLineBreaks:(bool)skipLineBreaks);
FORWARD_TO(self.textActions, void, replaceRange:(NSRange)range withString:(NSString*)newString);
FORWARD_TO(self.textActions, void, replaceString:(NSString*)string withString:(NSString*)newString atIndex:(NSUInteger)index);
FORWARD_TO(self.textActions, void, removeRange:(NSRange)range);
FORWARD_TO(self.textActions, void, moveStringFrom:(NSRange)range to:(NSInteger)position actualString:(NSString*)string);
FORWARD_TO(self.textActions, void, moveStringFrom:(NSRange)range to:(NSInteger)position);
FORWARD_TO(self.textActions, void, moveScene:(OutlineScene*)sceneToMove from:(NSInteger)from to:(NSInteger)to);
FORWARD_TO(self.textActions, void, removeTextOnLine:(Line*)line inLocalIndexSet:(NSIndexSet*)indexSet);

/// Removes an attribute from the text storage
- (void)removeAttribute:(NSString*)key range:(NSRange)range
{
    if (key == nil) return;
    [self.textView.textStorage removeAttribute:key range:range];
}
/// Adds an attribute to the text storage
- (void)addAttribute:(NSString*)key value:(id)value range:(NSRange)range
{
    if (value == nil) return;
    [self.textView.textStorage addAttribute:key value:value range:range];
}
/// Adds attributes to the text storage
- (void)addAttributes:(NSDictionary*)attributes range:(NSRange)range
{
    if (attributes == nil) return;
    [self.textView.textStorage addAttributes:attributes range:range];
}


#pragma mark - Creating the actual document file

- (NSString*)createDocumentFile
{
    return [self createDocumentFileWithAdditionalSettings:nil];
}

/// Returns the string to be stored as the document. After merging together content and settings, the string is returned to `dataOfType:`. If you want to add additional settings at save-time, you can provide them in a dictionary.
- (NSString*)createDocumentFileWithAdditionalSettings:(NSDictionary*)additionalSettings
{
    
    // Save tagged ranges
    // [self saveTags];
    
    // For async saving & thread safety, make a copy of the lines array
    NSAttributedString *attrStr = self.getAttributedText;
    NSString *content = self.parser.screenplayForSaving;
    if (content == nil) {
        NSLog(@"ERROR: Something went horribly wrong, trying to crash the app to avoid data loss.");
        @throw NSInternalInconsistencyException;
    }
    
    // Resort to content buffer if needed
    if (content == nil) content = self.contentCache;
    
    // Save added/removed ranges
    // This saves the revised ranges into Document Settings
    NSDictionary *revisions = [BeatRevisions rangesForSaving:attrStr];
    [self.documentSettings set:DocSettingRevisions as:revisions];
    
    // Save current revision color
    [self.documentSettings setString:DocSettingRevisionColor as:self.revisionColor];
    
    // Save changed indices (why do we need this? asking for myself. -these are lines that had something removed rather than added, a later response)
    [self.documentSettings set:DocSettingChangedIndices as:[BeatRevisions changedLinesForSaving:self.lines]];
    
    // Store currently running plugins (which should be saved)
    [self.documentSettings set:DocSettingActivePlugins as:[self runningPluginsForSaving]];
        
    // Save reviewed ranges
    NSArray *reviews = [_review rangesForSavingWithString:attrStr];
    [self.documentSettings set:DocSettingReviews as:reviews];
    
    // Save heading/section info
    [self.documentSettings set:DocSettingHeadingUUIDs as:self.parser.outlineUUIDs];
    
    // Save caret position
    [self.documentSettings setInt:DocSettingCaretPosition as:self.textView.selectedRange.location];
    
    #if TARGET_OS_OSX
        [self unblockUserInteraction];
    #endif
    
    NSString * settingsString = [self.documentSettings getSettingsStringWithAdditionalSettings:additionalSettings];
    NSString * result = [NSString stringWithFormat:@"%@%@", content, (settingsString) ? settingsString : @""];
    
    [self documentWasSaved];
    
    return result;
}


#pragma mark - Revisions

- (void)setRevisionColor:(NSString *)revisionColor
{
    [self.documentSettings setString:DocSettingRevisionColor as:revisionColor];
}
- (NSString*)revisionColor
{
    NSString* revisionColor = [self.documentSettings getString:DocSettingRevisionColor];
    if (revisionColor == nil) revisionColor = BeatRevisions.defaultRevisionColor;
    return revisionColor;
}


- (void)bakeRevisions
{
    [BeatRevisions bakeRevisionsIntoLines:self.parser.lines.copy text:self.getAttributedText];
}

- (NSDictionary*)revisedRanges
{
    NSDictionary *revisions = [BeatRevisions rangesForSaving:self.getAttributedText];
    return revisions;
}

- (NSArray*)shownRevisions
{
    NSArray<NSString*>* hiddenRevisions = [self.documentSettings get:DocSettingHiddenRevisions];
    NSMutableArray* shownRevisions = BeatRevisions.revisionColors.mutableCopy;
    
    if (hiddenRevisions.count > 0) {
        [shownRevisions removeObjectsInArray:hiddenRevisions];
    }
    
    return shownRevisions;
}

- (nonnull NSString *)fileNameString {
    NSLog(@"fileNameString: Override in OS-specific implementation");
    return @"";
}


#pragma mark - Font size

/// Returns current default font point size
- (CGFloat)fontSize
{
    return BeatFonts.sharedFonts.courier.pointSize;
}


#pragma mark - Plugin support

/// Returns every plugin that should be registered to be saved
- (NSArray*)runningPluginsForSaving
{
    NSMutableArray* plugins = NSMutableArray.new;
    for (NSString* pluginName in self.runningPlugins.allKeys) {
        id<BeatPluginInstance> plugin = (id<BeatPluginInstance>) self.runningPlugins[pluginName];
        if (!plugin.restorable) continue;
        
        [plugins addObject:pluginName];
    }
    
    return plugins;
}


- (void)documentWasSaved
{
    NSLog(@"documentWasSaved: Override in OS-specific implementation");
}



@end
