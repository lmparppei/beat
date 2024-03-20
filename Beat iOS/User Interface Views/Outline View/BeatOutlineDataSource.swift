//
//  BeatOutlineDataSource.swift
//  Beat iOS
//
//  Created by Lauri-Matti Parppei on 27.6.2023.
//  Copyright © 2023 Lauri-Matti Parppei. All rights reserved.
//

import Foundation
import BeatCore
import BeatParsing

@objc class BeatOutlineDataProvider:NSObject {
	var dataSource:UITableViewDiffableDataSource<Int,OutlineDataItem>
	var delegate:BeatEditorDelegate
	weak var tableView:UITableView?
	
	@objc init(delegate:BeatEditorDelegate, tableView:UITableView) {
		self.delegate = delegate
		self.tableView = tableView
		
		self.dataSource = UITableViewDiffableDataSource(tableView: tableView, cellProvider: { tableView, indexPath, itemIdentifier in
			let cell = tableView.dequeueReusableCell(withIdentifier: "Scene") as! BeatOutlineViewCell
			
			let scene = delegate.parser.outline[indexPath.row] as! OutlineScene
			let string = OutlineViewItem.withScene(scene,
												   currentScene: OutlineScene(),
												   sceneNumber: BeatUserDefaults().getBool(BeatSettingShowSceneNumbersInOutline),
												   synopsis: BeatUserDefaults().getBool(BeatSettingShowSynopsisInOutline),
												   notes: BeatUserDefaults().getBool(BeatSettingShowNotesInOutline),
												   markers: BeatUserDefaults().getBool(BeatSettingShowMarkersInOutline),
												   isDark: true)
			
			cell.representedScene = scene
			cell.textLabel?.attributedText = string
			
			return cell
		})
		super.init()
		
		// Create initial snapshot
		if let snapshot = self.initialSnapshot() {
			self.dataSource.apply(snapshot, animatingDifferences: true)
		}
	}
	
	@objc func update() {
		guard let outline = delegate.parser.outline as? [OutlineScene] else { return }
		
		let items:[OutlineDataItem] = outline.map { OutlineDataItem(with: $0) }
		
		var snapshot = NSDiffableDataSourceSnapshot<Int, OutlineDataItem>()
		snapshot.appendSections([0])
		snapshot.appendItems(items)
		
		self.dataSource.applySnapshotUsingReloadData(snapshot)		
	}
	
	func initialSnapshot() -> NSDiffableDataSourceSnapshot<Int, OutlineDataItem>? {
		guard let outline = delegate.parser.outline as? [OutlineScene] else { return nil }
		
		var items:[OutlineDataItem] = []
		for scene in outline {
			let item = OutlineDataItem(with: scene)
			items.append(item)
		}
		
		var snapshot = NSDiffableDataSourceSnapshot<Int, OutlineDataItem>()
		snapshot.appendSections([0])
		snapshot.appendItems(items)
		
		return snapshot
	}
}

class OutlineDataItem:Hashable {
	var string:String
	var color:String
	var synopsis:[Line]
	var beats:[Storybeat]
	var markers:[[String:String]]
	var sceneNumber:String
	var uuid:UUID
	var range:NSRange
	var selected:Bool
	weak var scene:OutlineScene?
	
	init(with scene:OutlineScene) {
		self.string = scene.string
		self.color = scene.color
		self.synopsis = scene.synopsis as! [Line]
		self.beats = scene.beats as! [Storybeat]
		self.markers = scene.markers as! [[String : String]]
		self.sceneNumber = scene.sceneNumber ?? ""
		self.uuid = scene.line.uuid ?? UUID()
		self.range = scene.range()
		self.selected = false
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(uuid)
		hasher.combine(string)
		hasher.combine(color)
		hasher.combine(markers)
	}

	static func == (lhs: OutlineDataItem, rhs: OutlineDataItem) -> Bool {
		return lhs.uuid == rhs.uuid
	}
}
