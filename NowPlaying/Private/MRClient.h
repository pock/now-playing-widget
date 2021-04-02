//
//  MRClient.h
//  NowPlaying
//
//  Created by Pierluigi Galdi on 02/04/21.
//  Copyright © 2021 Pierluigi Galdi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MRClient: NSObject
- (nonnull NSString *)bundleIdentifier;
- (nullable NSString *)parentApplicationBundleIdentifier;
- (nonnull NSString *)displayName;
- (nullable id)appIcon;
@end
