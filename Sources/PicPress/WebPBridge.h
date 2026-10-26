//
//  WebPBridge.h
//  PicPress
//
//  Thin C shim over libwebp so Swift never has to touch WebPPicture directly.
//

#ifndef PP_WEBP_BRIDGE_H
#define PP_WEBP_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Encodes straight (non-premultiplied) 8-bit RGBA pixels into a WebP bitstream.
///
/// - Parameters:
///   - rgba:   Tightly described RGBA buffer, `stride` bytes per row.
///   - width:  Image width in pixels (1...16383).
///   - height: Image height in pixels (1...16383).
///   - stride: Bytes per row, usually `width * 4`.
///   - quality: 0...100, higher is better quality / bigger file.
///   - method: 0...6 encoder effort, higher is slower and smaller.
///   - out_data / out_size: Receives a malloc'd buffer owned by the caller.
///     Release it with `pp_webp_free`.
///
/// - Returns: 0 on success, non-zero on failure (see bridge implementation).
int pp_webp_encode(const uint8_t *rgba,
                   int width,
                   int height,
                   int stride,
                   float quality,
                   int method,
                   uint8_t **out_data,
                   size_t *out_size);

/// Frees a buffer returned by `pp_webp_encode`.
void pp_webp_free(void *ptr);

/// Encoder version as a 24-bit integer (major << 16 | minor << 8 | patch).
int pp_webp_encoder_version(void);

#ifdef __cplusplus
}
#endif

#endif /* PP_WEBP_BRIDGE_H */
