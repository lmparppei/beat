//
//  BeatDocumentViewController Extensions.swift
//  Beat iOS
//
//  Created by Lauri-Matti Parppei on 7.7.2023.
//  Copyright © 2023 Lauri-Matti Parppei. All rights reserved.
//

import UIKit
import BeatCore
import BeatFileExport

extension BeatDocumentViewController {
	
	@objc func setupTitleBar() {
		self.titleBar?.title = self.fileNameString()
		
		setupTitleMenus()
	}
	
	/// Sets up the rename/document menu
	@objc func setupTitleMenus() {
		// Basic iPad menu scheme
		let documentProperties = UIDocumentProperties(url: document.fileURL)
		if let itemProvider = NSItemProvider(contentsOf: document.fileURL) {
			documentProperties.dragItemsProvider = { _ in
				[UIDragItem(itemProvider: itemProvider)]
			}
			documentProperties.activityViewControllerProvider = {
				UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)
			}
		}
		
		navigationItem.documentProperties = documentProperties
		
		navigationItem.titleMenuProvider = { suggestions in
			var items = suggestions
			
			items.append(UICommand(title: "Create PDF...", action: #selector(self.openExportPanel)))
			items.append(UIMenu(title: "Export", options: .displayInline, children: [
				UIAction(title: "Export Final Draft File...", handler: { _ in
					self.exportFile(type: "FDX")
				}),
				UIAction(title: "Export Fountain Outline...", handler: { _ in
					self.exportFile(type: "Outline")
				})
			]))
			
			return UIMenu(children: items)
		}
		
		
		let screenplayMenu = UIMenu(options: [], children: [
			UIDeferredMenuElement.uncached { [weak self] completion in
				guard let self else { completion([]); return }
				
				let sceneNumberStart = self.documentSettings.getInt(DocSettingSceneNumberStart)
				let sceneNumberString = String(sceneNumberStart)
				
				let items:[UIMenuElement] = [
					UIAction(title: "Add title page", image: UIImage(systemName: "info"), handler: { (_) in
						self.formattingActions.addTitlePage(self)
					}),
					UIMenu(title: "", options: .displayInline, children: [
						UIAction(title: "Set First Scene Number", image: UIImage(systemName: "number"), handler: { _ in
							BeatNumberInput.presentNumberInputPrompt(on: self, title: "First Scene Number", message: "Scene numbering sequence begins from this number and automatically increments. Must be at least 1.", currentvalue: sceneNumberString) { value in
								if var v = value {
									if v < 1 { v = 1 }
									self.documentSettings.setInt(DocSettingSceneNumberStart, as: v)
									self.parser.updateOutline()
									self.textView.layoutManager.invalidateDisplay(forCharacterRange: NSMakeRange(0, self.text().count))
								}
							}
						}),
						UIAction(title: "Lock scene numbers", image: UIImage(systemName: "lock"), handler: { (_) in
							self.formattingActions.lockSceneNumbers(self)
						}),
						UIAction(title: "Remove locked scene numbers", image: UIImage(systemName: "lock.open"), handler: { (_) in
							self.formattingActions.unlockSceneNumbers(self)
						}),
					]),
					UIMenu(title: "Pagination Options", image: UIImage(systemName: "book.pages"), children: [
						UIMenu(title: "Page Numbering Begins From...", children: [
							UIAction(title: "Any Content", state: self.documentSettings.getInt(DocSettingPageNumberingMode) == BeatPageNumberingMode.default.rawValue ? .on : .off, handler: { _ in
								self.documentSettings.setInt(DocSettingPageNumberingMode, as: BeatPageNumberingMode.default.rawValue)
								self.resetPreview()
							}),
							UIAction(title: "First Scene", state: self.documentSettings.getInt(DocSettingPageNumberingMode) == BeatPageNumberingMode.firstScene.rawValue ? .on : .off, handler: { _ in
								self.documentSettings.setInt(DocSettingPageNumberingMode, as: BeatPageNumberingMode.firstScene.rawValue)
								self.resetPreview()
							}),
							UIAction(title: "First Forced Page Break", state: self.documentSettings.getInt(DocSettingPageNumberingMode) == BeatPageNumberingMode.firstPageBreak.rawValue ? .on : .off, handler: { _ in
								self.documentSettings.setInt(DocSettingPageNumberingMode, as: BeatPageNumberingMode.firstPageBreak.rawValue)
								self.resetPreview()
							})
						]),
						UIAction(title: "Set First Page Number...", handler: { _ in
							BeatNumberInput.presentNumberInputPrompt(on: self, title: "First Page Number", message: "Pagination begins from this number. Must be at least 1.", currentvalue: String(self.documentSettings.getInt(DocSettingFirstPageNumber))) { value in
								guard let value else { return }
								self.documentSettings.setInt(DocSettingFirstPageNumber, as: max(value, 1))
								self.resetPreview()
							}
						})
					]),
					UIMenu(options: .displayInline, children: [
						UIAction(title: "Screenplay statistics", handler: { (_) in
							self.pluginAgent.runPlugin(withName: "BeatStatistics")
						})
					]),
					UIMenu(options: .displayInline, children: [
						UIAction(title: "All Settings...", image: UIImage(systemName: "gear"), handler: { (_) in
							self.openSettings(self)
						})
					]),

					/*
					 UIMenu(title: "Plugins", options: [], children: [
					 UIDeferredMenuElement.uncached { [weak self] completion in
					 var actions = [UIMenuElement]()
					 let runningPlugins = self?.runningPlugins.allKeys as? [String] ?? []
					 
					 let pluginItem = UIAction(title: "Run Test Plugin") { _ in
					 self?.pluginAgent.runPlugin(withName: "FTOutliner")
					 }
					 
					 if runningPlugins.contains(where: { $0 == "FTOutliner" } ) {
					 pluginItem.state = .on
					 }
					 
					 actions.append(pluginItem)
					 
					 completion(actions)
					 }
					 ])
					 */
				]
				
				completion(items)
			}
		])
				
		self.screenplayButton?.menu = screenplayMenu
		self.screenplayButton?.primaryAction = nil
		
		// For iPhone, we need to do some adjustments.
		if UIDevice.current.userInterfaceIdiom == .phone {
			var menuItems = self.screenplayButton?.menu?.children
			
			let additionalButtons = [
				UIMenu(options: [.displayInline], children: [
					UIAction(title: "Document Settings", image: UIImage(systemName: "doc.badge.gearshape"), handler: { (_) in
						// Note!!! To avoid weird stuff, we'll need to supply the top button as sender.
						if let button = self.screenplayButton { self.openQuickSettings(button) }
					})
				]),
				UIMenu(options: [.displayInline], children: [
					UIAction(title: "Show Preview", image: UIImage(named: "eye.fill"), handler: { (_) in
						self.togglePreview(self)
					}),
					UIAction(title: "Show Index Cards", image: UIImage(named: "square.grid.2x2.fill"), handler: { (_) in
						self.toggleCards(self)
					})
				])
			]
			
			menuItems?.insert(contentsOf: additionalButtons, at: 0)
			self.screenplayButton?.menu = UIMenu(children: menuItems ?? [])
		}
	}
}

/// Support for plugin view floating buttons
fileprivate var pluginViewControllers:[BeatPluginHTMLViewController] = []
fileprivate var pluginViewButtons:[BeatPluginHTMLViewController:UIButton] = [:]
extension BeatDocumentViewController {
	
	@objc func registerPluginViewController(_ viewController:BeatPluginHTMLViewController) {
		guard pluginViewControllers.firstIndex(of: viewController) == nil else { return }
		
		pluginViewControllers.append(viewController)
		
		
		let button = UIButton()
		button.backgroundColor = BeatColors.color("blue")
		
		let c = viewController.name?.first ?? "?"
		let title = String(c)
		
		button.title = title
		
		button.frame = CGRectMake(15.0, 15.0, 60.0, 60.0)
		button.layer.cornerRadius = button.frame.width / 2
		button.titleLabel?.adjustsFontSizeToFitWidth = true
		button.titleLabel?.font = UIFont.systemFont(ofSize: 20.0)
		
		self.view.addSubview(button)
		
		pluginViewButtons[viewController] = button
	}
	
	@objc func unregisterPluginViewController(_ viewController:BeatPluginHTMLViewController) {
		pluginViewControllers.removeObject(object: viewController)
		
		let button = pluginViewButtons[viewController]
		button?.removeFromSuperview()
		pluginViewButtons.removeValue(forKey: viewController)
	}
}

@objc public extension BeatDocumentViewController {
	
	@IBAction func nextScene(_ sender:Any!) {
		if let line = self.parser.nextOutlineItem(of: .heading, from: self.selectedRange().location) {
			self.scroll(to: line)
		}
	}
	
	@IBAction func previousScene(_ sender:Any!) {
		if let line = self.parser.previousOutlineItem(of: .heading, from: self.selectedRange().location) {
			self.scroll(to: line)
		}
	}
	
}


@objc public extension UIViewController {
	@objc func embed(_ viewController:UIViewController, inView view:UIView){
		viewController.willMove(toParent: self)
		viewController.view.frame = view.bounds

		view.addSubview(viewController.view)
		self.addChild(viewController)

		viewController.didMove(toParent: self)
	}
}
