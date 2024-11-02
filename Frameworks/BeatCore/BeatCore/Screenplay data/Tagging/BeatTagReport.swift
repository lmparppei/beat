//
//  BeatTagReport.swift
//  BeatCore
//
//  Created by Lauri-Matti Parppei on 19.8.2024.
//

import Foundation
import BeatParsing

public extension BeatTagging {
    
    class var types:[BeatTagType] {
        var types:[BeatTagType] = []
        for i in 0...100 {
            if let type = BeatTagType(rawValue: i) {
                types.append(type)
            } else {
                break
            }
        }
        return types
    }
    
    func byType(_ types:[BeatTagType]) -> NSAttributedString {
        let text = NSMutableAttributedString()
                                                
        for type in types {
            // For some reason Swift doesn't read our types correctly, we'll need to cast them
            let typeText = NSMutableAttributedString()
            
            for scene in self.delegate.parser.scenes() as? [OutlineScene] ?? [] {
                let singleListing = singleTagListing(for: scene, type: type)
                if singleListing.string.count > 0 {
                    typeText.append(singleListing)
                }
            }
            
            // Add text for this tag type if needed
            if typeText.string.count > 0 {
                // Page break after each tag (excluding first page)
                if text.length > 0 {
                    text.append(NSAttributedString(string: "\u{0c}"))
                }
                
                text.append(self.pageHeader(type: type))
                text.append(typeText)
            }
        }
        
        return text
    }
    
    func singleTagListing(for scene:OutlineScene, type:BeatTagType) -> NSAttributedString {
        let text = NSMutableAttributedString()
        var foundTags:[String] = []
        
        let lines = self.delegate.parser.lines(for: scene) as? [Line] ?? []
                        
        for line in lines {
            for value in line.tags as? [[String:Any]] ?? [] {
                if let tag = value["tag"] as? BeatTag, tag.type == type, !foundTags.contains(tag.definition.name) {
                    foundTags.append(tag.definition.name)
                }
            }
        }
        
        // If no tags were found, return empty string
        guard foundTags.count > 0 else { return text }
                
        let font = BXFont.systemFont(ofSize: 12.0)
        let headingFont = BXFont(name: "Courier-Bold", size: 12.0)!
        
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacingBefore = 12.0
        headingStyle.paragraphSpacing = 12.0

        let list = NSTextList(markerFormat: .disc, options: 0)
        let marker = list.marker(forItemNumber: 0)
        
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        style.firstLineHeadIndent = 30.0
        style.headIndent = 36.0
                
        let heading = NSAttributedString(string: scene.sceneNumber + " - " + scene.line.stripFormatting() + "\n", attributes: [.font: headingFont, .paragraphStyle: headingStyle])
        text.append(heading)
        
        for foundTag in foundTags {
            text.append(NSAttributedString(string: marker + " " + foundTag + "\n", attributes: [.font: font, .paragraphStyle: style]))
        }
        
        return text
    }
    
    func pageHeader(type: BeatTagType) -> NSAttributedString {
        let typeKey = BeatTagging.key(for: type)
        
        let pageHeaderFont = BXFont.boldSystemFont(ofSize: 16.0)
        let pageHeaderStyle = NSMutableParagraphStyle()
        pageHeaderStyle.paragraphSpacingBefore = 12.0
        
        let pageHeading = NSMutableAttributedString(string: BeatTagging.localizedTagName(for: typeKey), attributes: [.font: pageHeaderFont, .paragraphStyle: pageHeaderStyle])
                
        /*
        // macOS PDF export doesn't support image attachments for some rason, so we are skipping this step for now
        if #available(macOS 11.0, *) {
            if let iconName = BeatTagging.tagIcons()[NSNumber(value: type.rawValue)],
                let image = BXImage.init(systemSymbolName: iconName, accessibilityDescription: "") {
                
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRectMake(0.0, (pageHeaderFont.pointSize - image.size.height) / 2 - 2.0, image.size.width, image.size.height)
                pageHeading.insert(NSAttributedString(attachment: attachment), at: 0)
            }
        }
        */
        
        pageHeading.append(NSAttributedString(string: "\n\u{00A0} \u{0009} \u{00A0}\n", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: BXColor.black]))
        
        return pageHeading
    }
    
}