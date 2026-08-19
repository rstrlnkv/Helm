// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

#import "HelmLaunch.h"

NSErrorDomain const HelmLaunchErrorDomain = @"HelmLaunchErrorDomain";

NSString *const HelmLaunchExceptionNameKey = @"HelmLaunchExceptionName";

BOOL HelmLaunchTask(NSTask *task, NSError * _Nullable * _Nullable error) {
    @try {
        return [task launchAndReturnError:error];
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *name = exception.name ?: @"NSException";
            *error = [NSError errorWithDomain:HelmLaunchErrorDomain
                                         code:1
                                     userInfo:@{ HelmLaunchExceptionNameKey: name }];
        }
        return NO;
    }
}
