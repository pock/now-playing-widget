//
//  Preferences.swift
//  NowPlaying
//
//  Created by Pierluigi Galdi on 08/01/2020.
//  Copyright © 2020 Pierluigi Galdi. All rights reserved.
//

import Defaults

extension NSNotification.Name {
    static let didChangeNowPlayingWidgetStyle = NSNotification.Name("didChangeNowPlayingWidgetStyle")
}

extension Defaults.Keys {
    static let nowPlayingWidgetStyle      = Defaults.Key<NowPlayingWidgetStyle>("nowPlayingWidgetStyle", default: .default)
	static let hideNowPlayingIfNoMedia    = Defaults.Key<Bool>("hideNowPlayingIfNoMedia", default: false)
    static let animateIconWhilePlaying    = Defaults.Key<Bool>("animateIconWhilePlaying", default: true)
	static let showMediaArtwork			  = Defaults.Key<Bool>("showMediaArtwork",		  default: false)
	static let invertSwipeGesture		  = Defaults.Key<Bool>("invertSwipeGesture",	  default: true)
}
