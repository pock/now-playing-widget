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
        				
/// Make sure to include `PockKit` in your Podfile and run `pod install`
				        
class NowPlayingWidget: PKWidget {
    var identifier: NSTouchBarItem.Identifier = NSTouchBarItem.Identifier(rawValue: "NowPlayingWidget")
    var customizationLabel: String = "NowPlaying"
    var view: NSView!

    required init() {
        self.view = NSButton(title: "NowPlaying", target: self, action: #selector(printMessage))
    }
    
    @objc private func printMessage() {
        print("[NowPlayingWidget]: Hello, World!")
    }
        
}
