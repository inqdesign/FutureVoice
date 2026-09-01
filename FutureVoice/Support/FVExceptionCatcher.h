#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, converting any NSException it raises into an NSError.
///
/// Exists for exactly one class of caller: AVFAudio APIs that RAISE on
/// transient conditions Swift cannot catch — `installTapOnBus` during a
/// route transition took the whole app down twice on 2026-09-01
/// (CreateRecordingTap, SIGABRT). Through here, the same moment becomes a
/// recoverable error the audio stack can retry.
BOOL FVCatchException(void (NS_NOESCAPE ^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
