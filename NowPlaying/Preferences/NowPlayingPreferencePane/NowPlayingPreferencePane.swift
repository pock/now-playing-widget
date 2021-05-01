//
//  NowPlayingPreferencePane.swift
//  Pock
//
//  Created by Pierluigi Galdi on 14/12/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Cocoa
import PockKit

class NowPlayingPreferencePane: NSViewController, PKWidgetPreference {
    
    static var nibName: NSNib.Name = "NowPlayingPreferencePane"
    
    // MARK: UI Elements
	
	@IBOutlet private weak var defaultApplicationIcon: NSImageView!
	@IBOutlet private weak var defaultApplicationName: NSTextField!
	
    @IBOutlet private weak var imagesStackView:         NSStackView!
    @IBOutlet private weak var defaultRadioButton:      NSButton!
    @IBOutlet private weak var onlyInfoRadioButton:     NSButton!
    @IBOutlet private weak var playPauseRadioButton:    NSButton!
	
    @IBOutlet private weak var hideWidgetIfNoMedia:     NSButton!
    @IBOutlet private weak var animateIconWhilePlaying: NSButton!
	@IBOutlet private weak var showMediaArtwork:		NSButton!
	@IBOutlet private weak var invertSwipeGesture:		NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
		switch NowPlayingWidgetStyle(rawValue: Preferences[.nowPlayingWidgetStyle]) ?? .default {
        case .default:
            defaultRadioButton.state = .on
        case .onlyInfo:
            onlyInfoRadioButton.state = .on
        case .playPause:
            playPauseRadioButton.state = .on
        }
		updateDefaultApplicationUIElements()
        updateButtonsState()
        setupImageViewClickGesture()
    }
    
	private func updateDefaultApplicationUIElements() {
		let bundleIdentifier: String = Preferences[.defaultPlayer]
		defaultApplicationIcon.image = NSWorkspace.shared.applicationIcon(for: bundleIdentifier)
		defaultApplicationName.stringValue = NSWorkspace.shared.applicationName(for: bundleIdentifier) ?? ""
	}
	
	private func updateButtonsState() {
		hideWidgetIfNoMedia.state     = Preferences[.hideNowPlayingIfNoMedia] ? .on : .off
		animateIconWhilePlaying.state = Preferences[.animateIconWhilePlaying] ? .on : .off
		showMediaArtwork.state 		  = Preferences[.showMediaArtwork] 	   	  ? .on : .off
		invertSwipeGesture.state 	  = Preferences[.invertSwipeGesture] 	  ? .on : .off
	}
	
    private func setupImageViewClickGesture() {
        imagesStackView.arrangedSubviews.forEach({
            $0.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didSelectRadioButton(_:))))
        })
    }
	
	@IBAction private func didSelectChooseDefaultApplicationButton(_ control: Any?) {
		guard let window = self.view.window else {
			return
		}
		let openPanel = NSOpenPanel()
		openPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!
		openPanel.canChooseDirectories = false
		openPanel.canChooseFiles = true
		openPanel.allowsMultipleSelection = false
		openPanel.allowedFileTypes = ["app"]
		openPanel.beginSheetModal(for: window, completionHandler: { [weak self] result in
			if result == NSApplication.ModalResponse.OK {
				guard let self = self,
						let pathUrl = openPanel.url,
						let bundleIdentifier = Bundle(url: pathUrl)?.bundleIdentifier else {
					return
				}
				Preferences[.defaultPlayer] = bundleIdentifier
				self.updateDefaultApplicationUIElements()
				NotificationCenter.default.post(name: .mrMediaRemoteNowPlayingApplicationDidChange, object: nil)
			}
		})
	}
    
    @IBAction private func didSelectRadioButton(_ control: AnyObject) {
        let view = (control as? NSGestureRecognizer)?.view ?? control
        switch view.tag {
        case 0:
			Preferences[.nowPlayingWidgetStyle] = NowPlayingWidgetStyle.default.rawValue
            defaultRadioButton.state   = .on
            onlyInfoRadioButton.state  = .off
            playPauseRadioButton.state = .off
        case 1:
			Preferences[.nowPlayingWidgetStyle] = NowPlayingWidgetStyle.onlyInfo.rawValue
            defaultRadioButton.state   = .off
            onlyInfoRadioButton.state  = .on
            playPauseRadioButton.state = .off
        case 2:
			Preferences[.nowPlayingWidgetStyle] = NowPlayingWidgetStyle.playPause.rawValue
            defaultRadioButton.state   = .off
            onlyInfoRadioButton.state  = .off
            playPauseRadioButton.state = .on
        default:
            return
        }
		NotificationCenter.default.post(name: .mrPlaybackQueueContentItemsChanged, object: nil)
		NotificationCenter.default.post(name: Notification.Name(didChangeNowPlayingWidgetStyle), object: nil)
    }
    
    @IBAction private func didChangeCheckboxState(_ button: NSButton?) {
        guard let button = button else {
            return
        }
        switch button.tag {
        case 0:
			Preferences[.hideNowPlayingIfNoMedia] = button.state == .on
        case 1:
			Preferences[.animateIconWhilePlaying] = button.state == .on
			if Preferences[.showMediaArtwork] {
				Preferences[.showMediaArtwork] = !Preferences[.animateIconWhilePlaying]
			}
			updateButtonsState()
		case 2:
			Preferences[.showMediaArtwork] = button.state == .on
			if Preferences[.animateIconWhilePlaying] {
				Preferences[.animateIconWhilePlaying] = !Preferences[.showMediaArtwork]
			}
			updateButtonsState()
		case 3:
			Preferences[.invertSwipeGesture] = button.state == .on
        default:
            return
        }
		NotificationCenter.default.post(name: .mrPlaybackQueueContentItemsChanged, object: nil)
        NotificationCenter.default.post(name: Notification.Name(didChangeNowPlayingWidgetStyle), object: nil)
    }
    
}
