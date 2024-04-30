//
//  BeatTextIO.h
//  BeatCore
//
//  Created by Lauri-Matti Parppei on 18.2.2023.
//

#import <TargetConditionals.h>
#import <JavaScriptCore/JavaScriptCore.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#define BXTextView UITextView
#else
#import <Cocoa/Cocoa.h>
#define BXTextView NSTextView
#endif

#import <BeatCore/BeatEditorDelegate.h>

typedef NS_ENUM(NSUInteger, BeatMarkupStyle) {
    Block = 0,
    Bold,
    Italic,
    Underline,
    Note,
    Centered
};

@class OutlineScene;
@class ContinuousFountainParser;
@class Line;

@protocol BeatTextIOExports <JSExport>
JSExportAs(replaceCharactersInRange,- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)string);
JSExportAs(addString, - (void)addString:(NSString*)string atIndex:(NSUInteger)index skipAutomaticLineBreaks:(bool)skipLineBreaks);
JSExportAs(remove, - (void)removeAt:(NSUInteger)index length:(NSUInteger)length);
JSExportAs(replaceRange, - (void)replaceRange:(NSRange)range withString:(NSString*)newString);
JSExportAs(moveString, - (void)moveStringFrom:(NSRange)range to:(NSInteger)position);

- (void)addNewParagraph:(NSString*)string;
@end

@protocol BeatTextIODelegate <BeatEditorDelegate>
@optional @property (nonatomic) NSUndoManager* undoManager;
- (void)textDidChange:(NSNotification *)notification;
- (BOOL)textView:(BXTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString;
@end

@interface BeatTextIO : NSObject <BeatTextIOExports>
@property (nonatomic, weak) id<BeatTextIODelegate> delegate;

- (instancetype)initWithDelegate:(id<BeatTextIODelegate>)delegate;

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)string;
- (void)addString:(NSString*)string atIndex:(NSUInteger)index;
- (void)addString:(NSString*)string atIndex:(NSUInteger)index skipAutomaticLineBreaks:(bool)skipLineBreaks;
- (void)removeAt:(NSUInteger)index length:(NSUInteger)length;
- (void)replaceRange:(NSRange)range withString:(NSString*)newString;
- (void)replaceString:(NSString*)string withString:(NSString*)newString atIndex:(NSUInteger)index;
- (void)removeRange:(NSRange)range;
- (void)moveStringFrom:(NSRange)range to:(NSInteger)position actualString:(NSString*)string;
- (void)moveStringFrom:(NSRange)range to:(NSInteger)position;
- (void)moveScene:(OutlineScene*)sceneToMove from:(NSInteger)from to:(NSInteger)to;
- (void)removeTextOnLine:(Line*)line inLocalIndexSet:(NSIndexSet*)indexSet;

/// Replaces characters with an **attributed string**. Only accepts registered Beat attributes.
- (void)replaceRange:(NSRange)range withAttributedString:(NSAttributedString *)attrString;

- (void)addNewParagraph:(NSString*)string;
- (void)addNewParagraph:(NSString*)string caretPosition:(NSInteger)newPosition;

- (void)addSection:(NSInteger)position;
- (void)addSynopsis:(NSInteger)position;
- (void)addShot:(NSInteger)position;

- (void)addCueExtension:(NSString*)extension onLine:(Line*)line;

- (bool)shouldAddLineBreaks:(Line*)currentLine range:(NSRange)affectedCharRange;
- (bool)shouldJumpOverParentheses:(NSString*)replacementString range:(NSRange)affectedCharRange;
- (void)matchParenthesesIn:(NSRange)affectedCharRange string:(NSString*)replacementString;
- (BOOL)shouldAddContdIn:(NSRange)affectedCharRange string:(NSString*)replacementString;

- (void)setColor:(NSString *)color forLine:(Line *)line;
- (void)setColor:(NSString *)color forScene:(OutlineScene *)scene;

- (void)addStoryline:(NSString*)storyline to:(OutlineScene*)scene;
- (void)removeStoryline:(NSString*)storyline from:(OutlineScene*)scene;

- (void)moveBlockUp:(NSArray<Line*>*)lines;
- (void)moveBlockDown:(NSArray<Line*>*)lines;

- (void)forceLineType:(LineType)lineType;
- (void)forceLineType:(LineType)type range:(NSRange)cursorLocation;

@end


