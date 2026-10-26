//
//  WebPBridge.c
//  PicPress
//

#include "WebPBridge.h"

#include <webp/encode.h>

int pp_webp_encode(const uint8_t *rgba,
                   int width,
                   int height,
                   int stride,
                   float quality,
                   int method,
                   uint8_t **out_data,
                   size_t *out_size) {
  if (out_data != NULL) *out_data = NULL;
  if (out_size != NULL) *out_size = 0;
  if (rgba == NULL || out_data == NULL || out_size == NULL) return 1;
  if (width <= 0 || height <= 0 || width > 16383 || height > 16383) return 1;
  if (stride < width * 4) return 1;

  WebPConfig config;
  if (!WebPConfigInit(&config)) return 2;

  if (quality < 0.0f) quality = 0.0f;
  if (quality > 100.0f) quality = 100.0f;
  if (method < 0) method = 0;
  if (method > 6) method = 6;

  config.quality = quality;
  config.method = method;
  config.alpha_quality = 100;    /* keep transparency lossless */
  config.alpha_compression = 1;
  config.thread_level = 1;
  if (!WebPValidateConfig(&config)) return 3;

  WebPPicture picture;
  if (!WebPPictureInit(&picture)) return 4;
  picture.width = width;
  picture.height = height;
  picture.use_argb = 1;

  WebPMemoryWriter writer;
  WebPMemoryWriterInit(&writer);
  picture.writer = WebPMemoryWrite;
  picture.custom_ptr = &writer;

  if (!WebPPictureImportRGBA(&picture, rgba, stride)) {
    WebPPictureFree(&picture);
    WebPMemoryWriterClear(&writer);
    return 5;
  }

  /* libwebp only emits an ALPH chunk when the picture really has
     transparency, so opaque inputs pay nothing for the RGBA import. */
  if (!WebPEncode(&config, &picture)) {
    WebPPictureFree(&picture);
    WebPMemoryWriterClear(&writer);
    return 6;
  }
  WebPPictureFree(&picture);

  if (writer.size == 0) {
    WebPMemoryWriterClear(&writer);
    return 7;
  }

  *out_data = writer.mem;
  *out_size = writer.size;
  writer.mem = NULL; /* ownership moves to the caller */
  return 0;
}

void pp_webp_free(void *ptr) { WebPFree(ptr); }

int pp_webp_encoder_version(void) { return WebPGetEncoderVersion(); }
