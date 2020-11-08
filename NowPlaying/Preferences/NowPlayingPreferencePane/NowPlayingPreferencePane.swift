//
//  NowPlayingPreferencePane.swift
//  Pock
//
//  Created by Pierluigi Galdi on 14/12/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Cocoa
import Defaults
import PockKit

class NowPlayingPreferencePane: NSViewController, PKWidgetPreference {
    
    static var nibName: NSNib.Name = "NowPlayingPreferencePane"
    
    /// UI Elements
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
        switch Defaults[.nowPlayingWidgetStyle] {
        case .default:
            defaultRadioButton.state = .on
        case .onlyInfo:
            onlyInfoRadioButton.state = .on
        case .playPause:
            playPauseRadioButton.state = .on
        }
        updateButtonsState()
        setupImageViewClickGesture()
    }
    
	private func updateButtonsState() {
		hideWidgetIfNoMedia.state     = Defaults[.hideNowPlayingIfNoMedia] ? .on : .off
		animateIconWhilePlaying.state = Defaults[.animateIconWhilePlaying] ? .on : .off
		showMediaArtwork.state 		  = Defaults[.showMediaArtwork] 	   ? .on : .off
		invertSwipeGesture.state 	  = Defaults[.invertSwipeGesture] 	   ? .on : .off
	}
	
    private func setupImageViewClickGesture() {
        imagesStackView.arrangedSubviews.forEach({
            $0.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didSelectRadioButton(_:))))
        })
    }
    
    @IBAction private func didSelectRadioButton(_ control: AnyObject) {
        let view = (control as? NSGestureRecognizer)?.view ?? control
        switch view.tag {
        case 0:
            Defaults[.nowPlayingWidgetStyle] = .default
            defaultRadioButton.state   = .on
            onlyInfoRadioButton.state  = .off
            playPauseRadioButton.state = .off
        case 1:
            Defaults[.nowPlayingWidgetStyle] = .onlyInfo
            defaultRadioButton.state   = .off
            onlyInfoRadioButton.state  = .on
            playPauseRadioButton.state = .off
        case 2:
            Defaults[.nowPlayingWidgetStyle] = .playPause
            defaultRadioButton.state   = .off
            onlyInfoRadioButton.state  = .off
            playPauseRadioButton.state = .on
        default:
            return
        }
        NotificationCenter.default.post(name: .didChangeNowPlayingWidgetStyle, object: nil)
    }
    
    @IBAction private func didChangeCheckboxState(_ button: NSButton?) {
        guard let button = button else {
            return
        }
        switch button.tag {
        case 0:
            Defaults[.hideNowPlayingIfNoMedia] = button.state == .on
        case 1:
            Defaults[.animateIconWhilePlaying] = button.state == .on
			if Defaults[.showMediaArtwork] {
				Defaults[.showMediaArtwork] = !Defaults[.animateIconWhilePlaying]
			}
			updateButtonsState()
			NotificationCenter.default.post(name: NSNotification.Name(rawValue: kMRMediaRemoteNowPlayingApplicationClientStateDidChange), object: nil)
		case 2:
			Defaults[.showMediaArtwork] = button.state == .on
			if Defaults[.animateIconWhilePlaying] {
				Defaults[.animateIconWhilePlaying] = !Defaults[.showMediaArtwork]
			}
			updateButtonsState()
			NotificationCenter.default.post(name: NSNotification.Name(rawValue: kMRMediaRemoteNowPlayingApplicationClientStateDidChange), object: nil)
		case 3:
			Defaults[.invertSwipeGesture] = button.state == .on
        default:
            return
        }
        NotificationCenter.default.post(name: .didChangeNowPlayingWidgetStyle, object: nil)
    }
    
}
