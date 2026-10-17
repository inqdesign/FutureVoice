//! Noise removal for the voice-clone recording, on the phone (2026-10-15).
//!
//! The clone recording used to be cleaned on the server by the previous TTS
//! vendor; Cartesia has no denoiser, and the founder picked DeepFilterNet3 with a
//! 30 dB attenuation limit by ear over Apple's Sound Isolation and over the
//! full-strength setting ("dfn30", Desktop/beta audio/denoise-free-2026-10-15).
//! The limit is the point: it leaves a little of the room in, and with it the
//! texture of the voice the clone is made from.
//!
//! One call: the whole take in, the whole take out, 48 kHz mono float. The
//! caller resamples. Same processing as DeepFilterNet's own `deep-filter -D`:
//! the STFT + lookahead delay is compensated, so output sample i lines up with
//! input sample i.

use std::panic::{catch_unwind, AssertUnwindSafe};

use df::tract::{DfParams, DfTract, RuntimeParams};
use ndarray::prelude::*;

/// Sample rate the model runs at.
#[no_mangle]
pub extern "C" fn fv_denoise_sample_rate() -> u32 {
    48_000
}

/// Denoise `n` samples of 48 kHz mono audio from `input` into `output`
/// (both `n` floats long, may not overlap). `atten_lim_db` caps how far the
/// noise is pushed down (30 = the app's setting; 100 = no cap).
///
/// Returns 0 on success, a negative number on any failure — in which case
/// `output` is unspecified and the caller keeps the original take.
///
/// # Safety
/// `input` and `output` must point to `n` valid floats each.
#[no_mangle]
pub unsafe extern "C" fn fv_denoise_48k(input: *const f32, n: usize, output: *mut f32, atten_lim_db: f32) -> i32 {
    if input.is_null() || output.is_null() || n == 0 {
        return -1;
    }
    let input = std::slice::from_raw_parts(input, n);
    let output = std::slice::from_raw_parts_mut(output, n);
    match catch_unwind(AssertUnwindSafe(|| run(input, output, atten_lim_db))) {
        Ok(Ok(())) => 0,
        Ok(Err(_)) => -2,
        Err(_) => -3,
    }
}

fn run(input: &[f32], output: &mut [f32], atten_lim_db: f32) -> Result<(), Box<dyn std::error::Error>> {
    // The CLI's own defaults (`deep-filter`, enhance_wav.rs), which is what
    // the founder listened to — the library's defaults differ (-10/30/20).
    let params = RuntimeParams::default()
        .with_atten_lim(atten_lim_db)
        .with_thresholds(-15., 35., 35.);
    let mut model = DfTract::new(DfParams::default(), &params)?;
    let hop = model.hop_size;
    let delay = model.fft_size - model.hop_size + model.lookahead * model.hop_size;
    // Pad the end by the delay (and up to a whole hop) so every input sample
    // has come out the other side once the delay is skipped.
    let len = (input.len() + delay).div_ceil(hop) * hop;
    let mut noisy = Array2::<f32>::zeros((1, len));
    noisy.slice_mut(s![0, ..input.len()]).assign(&ArrayView1::from(input));
    let mut enh = Array2::<f32>::zeros((1, len));
    for (ns_f, enh_f) in noisy
        .view()
        .axis_chunks_iter(Axis(1), hop)
        .zip(enh.view_mut().axis_chunks_iter_mut(Axis(1), hop))
    {
        model.process(ns_f, enh_f)?;
    }
    for (i, o) in output.iter_mut().enumerate() {
        *o = enh[[0, i + delay]];
    }
    Ok(())
}

/// Android: `VoiceDenoiser.nativeDenoise48k(input, attenLimDb)` — the same
/// call through JNI. Returns the cleaned samples, or null on any failure (the
/// app then uploads the take as it was).
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_roro_futurevoice_audio_VoiceDenoiser_nativeDenoise48k(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    input: jni::objects::JFloatArray,
    atten_lim_db: jni::sys::jfloat,
) -> jni::sys::jfloatArray {
    let null = std::ptr::null_mut();
    let n = match env.get_array_length(&input) { Ok(n) if n > 0 => n as usize, _ => return null };
    let mut samples = vec![0f32; n];
    if env.get_float_array_region(&input, 0, &mut samples).is_err() { return null }
    let mut out = vec![0f32; n];
    let ok = matches!(catch_unwind(AssertUnwindSafe(|| run(&samples, &mut out, atten_lim_db))), Ok(Ok(())));
    if !ok { return null }
    let Ok(result) = env.new_float_array(n as i32) else { return null };
    if env.set_float_array_region(&result, 0, &out).is_err() { return null }
    result.into_raw()
}
