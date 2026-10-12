#ifndef PREVIEW_BZIP2_H
#define PREVIEW_BZIP2_H
#include <stddef.h>
#include <stdint.h>

/// A narrow typed bridge to the system libbz2 streaming decoder. Swift sees only these
/// declarations: no bzlib types, no allocation callbacks and no compression entry points.

/// Opaque decoder; it owns one bz_stream and is created and destroyed only by this shim.
typedef struct preview_bzip2_decoder preview_bzip2_decoder;

typedef enum {
    /// Progress was made or more input is needed.
    PREVIEW_BZIP2_OK = 0,
    /// The end of the bzip2 stream was reached; unconsumed input may follow.
    PREVIEW_BZIP2_STREAM_END = 1,
    /// Bad magic, a failed checksum or an inconsistent block.
    PREVIEW_BZIP2_DATA_ERROR = -1,
    /// The library could not allocate its block buffers.
    PREVIEW_BZIP2_MEMORY_ERROR = -2,
    /// Any other library failure.
    PREVIEW_BZIP2_FAILURE = -3
} preview_bzip2_status;

/// Returns NULL if the decoder cannot be created.
preview_bzip2_decoder *preview_bzip2_create(void);

/// Consumes up to `*input_size` bytes and produces up to `*output_size` bytes. On return the two
/// sizes hold the bytes actually consumed and produced.
preview_bzip2_status preview_bzip2_decode(preview_bzip2_decoder *decoder,
                                          const uint8_t *input, size_t *input_size,
                                          uint8_t *output, size_t *output_size);

void preview_bzip2_destroy(preview_bzip2_decoder *decoder);
#endif
