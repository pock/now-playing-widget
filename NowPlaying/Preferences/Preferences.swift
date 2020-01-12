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
    static let defaultMusicPlayerName     = Defaults.Key<String>("defaultMusicPlayerName",     default: "Music")
    static let defaultMusicPlayerBundleID = Defaults.Key<String>("defaultMusicPlayerBundleID", default: "com.apple.Music")
    static let defaultMusicPlayerPath     = Defaults.Key<String>("defaultMusicPlayerPath",     default: "/System/Applications/Music.app")
    static let nowPlayingWidgetStyle      = Defaults.Key<NowPlayingWidgetStyle>("nowPlayingWidgetStyle", default: .default)
    static let hideNowPlayingIfNoMedia    = Defaults.Key<Bool>("hideNowPlayingIfNoMedia", default: false)
    static let animateIconWhilePlaying    = Defaults.Key<Bool>("animateIconWhilePlaying", default: true)
}
