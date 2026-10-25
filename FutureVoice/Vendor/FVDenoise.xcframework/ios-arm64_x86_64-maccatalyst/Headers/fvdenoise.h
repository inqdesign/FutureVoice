#pragma once
#include <stddef.h>
#include <stdint.h>
uint32_t fv_denoise_sample_rate(void);
int32_t fv_denoise_48k(const float *input, size_t n, float *output, float atten_lim_db);
