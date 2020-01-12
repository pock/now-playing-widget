//
//  NowPlayingWidget.swift
//  NowPlaying
//
//  Created by Pierluigi Galdi on 08/01/2020.
//  Copyright © 2020 Pierluigi Galdi. All rights reserved.
//

import Foundation
import AppKit
import PockKit
import Defaults
				        
class NowPlayingWidget: PKWidget {
    var identifier: NSTouchBarItem.Identifier = NSTouchBarItem.Identifier(rawValue: "NowPlayingWidget")
    var customizationLabel: String = "Now Playing"
    var view: NSView!

    private var nowPlayingView: NowPlayingView = NowPlayingView(frame: .zero)
    
    required init() {
        self.updateNowPLayingItemView()
        self.registerForNotifications()
        self.view = nowPlayingView
    }
    
    private func registerForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateNowPLayingItemView),
                                               name: NowPlayingHelper.kNowPlayingItemDidChange,
                                               object: nil
        )
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateNowPlayingStyle),
                                               name: .didChangeNowPlayingWidgetStyle,
                                               object: nil
        )
    }
    
    @objc private func updateNowPLayingItemView() {
        nowPlayingView.item = NowPlayingHelper.shared.nowPlayingItem
    }
    
    @objc private func updateNowPlayingStyle() {
        nowPlayingView.style = Defaults[.nowPlayingWidgetStyle]
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
        
}
