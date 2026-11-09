/// Which app these sources are built into: nawana, or the speech app
/// (`SpeechApp/`, the same sources with `SPEECH_APP` set). For the few
/// places a plain `if` reads better than an `#if`.
enum SpeechAppFlags {
    #if SPEECH_APP
    static let isSpeechApp = true
    #else
    static let isSpeechApp = false
    #endif
}
