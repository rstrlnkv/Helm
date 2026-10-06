// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

#import "HelmLaunch.h"
#import <objc/message.h>

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

NSNumber * _Nullable HelmReadNumber(NSObject *object, NSString *key) {
    @try {
        SEL getter = NSSelectorFromString(key);
        if (![object respondsToSelector:getter]) { return nil; }
        NSMethodSignature *shape = [object methodSignatureForSelector:getter];
        if (shape == nil || shape.numberOfArguments != 2 || strchr("df", shape.methodReturnType[0]) == NULL) { return nil; }
        if (shape.methodReturnType[0] == 'f') {
            return @(((float (*)(id, SEL))objc_msgSend)(object, getter));
        }
        return @(((double (*)(id, SEL))objc_msgSend)(object, getter));
    } @catch (...) {
        return nil;
    }
}
