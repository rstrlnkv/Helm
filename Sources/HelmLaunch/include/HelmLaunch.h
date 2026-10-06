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

/// The number an object answers for `key`, or nil where it gave none.
///
/// **The method that is invoked is the one that was examined.** The selector
/// named `key` is looked up on the object, its signature is read, and only a
/// method with no arguments and a `double` or `float` answer is called, directly
/// with that return type and nothing in between: no `get<Key>` or `is<Key>`
/// variant can answer in its place. What comes back is that method's number,
/// wrapped as it is.
///
/// **What collapses into nil:** the object does not respond to `key`; the method
/// of that name is not shaped as a getter of a floating-point number, so an
/// integer, a Boolean, an object or a void answer from it is refused and it is
/// not invoked; or something was thrown, an `NSException` or anything else.
///
/// A caller that must tell the first from the rest asks `respondsToSelector:`
/// itself before the call. No error is carried out: an exception's reason could
/// hold anything, and nothing here would act on its name.
///
/// What is not caught is a signal: one raised inside an accessor goes past the
/// `@try`.
///
/// The `@try` is in Objective-C for the reason `HelmLaunchTask` gives: a raise
/// from the accessor passes a Swift `catch`. For the return-type half of the
/// shape test, for the methods that are not invoked, for the catch-all and for
/// the answer coming from the examined method rather than a `get<Key>` variant
/// the evidence in this tree is the test family of `WindowCorner`, run against
/// stand-in objects; the argument count is tested by nothing. Not measured
/// against any system class's private accessor.
NSNumber * _Nullable HelmReadNumber(NSObject *object, NSString *key);

NS_ASSUME_NONNULL_END
