// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The domain a refusal that arrived as an exception is reported under.
///
/// Its own domain rather than one of Foundation's, so a caller can tell «the
/// launch threw» from «the launch failed», which are different kinds of news:
/// the second is a machine that could not start a tool, the first is Helm
/// having handed `NSTask` something it will not take.
extern NSErrorDomain const HelmLaunchErrorDomain;

/// The one key the error carries: the exception's **name**, and nothing else.
///
/// A reason string carries whatever `NSTask` was given — an argument, an
/// environment value, a path — and this app's log carries no names (`Redact`).
/// A name is a Foundation constant, so `NSInvalidArgumentException` says
/// everything a reader can act on and can be logged as it stands.
extern NSString *const HelmLaunchExceptionNameKey;

/// Starts a task, and answers with an error where `-launchAndReturnError:`
/// would have raised.
///
/// **`NSTask` does not only return errors — on some paths it raises**, and an
/// Objective-C exception goes straight past a Swift `catch`: there is nothing
/// in a Swift frame for it to land on, so the runtime reaches `std::terminate`
/// and the process aborts. `do { try process.run() } catch` therefore could not
/// guard this class of refusal at all, however carefully it was written, and a
/// build shipped that died with SIGABRT inside
/// `-[NSConcreteTask launchWithDictionary:error:]`.
///
/// Measured on macOS 27, and this is the shape of the fault: a NUL byte in an
/// argument or in an environment value raises, while a missing file, a bad
/// working directory, `EMFILE`, `EAGAIN` and `E2BIG` all come back as an
/// `NSError` the Swift call already handled. So the throwing paths are neither
/// enumerable nor rare enough to check for one by one — the crash in the field
/// came from a third one — and the fix has to be «catch whatever it raises»
/// rather than «forbid what we know raises».
///
/// **The `@try` is here rather than around a block called from Swift.** A block
/// would put a Swift frame between the raise and the handler, and an
/// Objective-C exception unwinding through Swift frames is not something Swift
/// promises to survive. Nothing but Objective-C stands between these braces.
BOOL HelmLaunchTask(NSTask *task, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
