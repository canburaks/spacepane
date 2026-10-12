#include "PreviewBZip2.h"
#include <bzlib.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

// Embed an autolink request for libbz2 in this object (clang honors the pragma with -fms-extensions,
// which Package.swift passes). Host tools that link the package's objects directly, without reading
// the package's linker settings, then resolve the BZ2_* symbols exactly as the package build does.
#pragma comment(lib, "bz2")

struct preview_bzip2_decoder {
    bz_stream stream;
};

preview_bzip2_decoder *preview_bzip2_create(void) {
    preview_bzip2_decoder *decoder = calloc(1, sizeof(*decoder));
    if (decoder == NULL) return NULL;
    // Verbosity 0; the faster, larger-memory decoder (about four bytes per block byte, at most 900 KB blocks).
    if (BZ2_bzDecompressInit(&decoder->stream, 0, 0) != BZ_OK) {
        free(decoder);
        return NULL;
    }
    return decoder;
}

preview_bzip2_status preview_bzip2_decode(preview_bzip2_decoder *decoder,
                                          const uint8_t *input, size_t *input_size,
                                          uint8_t *output, size_t *output_size) {
    if (decoder == NULL || input_size == NULL || output_size == NULL) return PREVIEW_BZIP2_FAILURE;
    // The library counts in unsigned int; larger spans are consumed over several calls.
    unsigned int available_in = *input_size > UINT_MAX ? UINT_MAX : (unsigned int)*input_size;
    unsigned int available_out = *output_size > UINT_MAX ? UINT_MAX : (unsigned int)*output_size;
    decoder->stream.next_in = (char *)(uintptr_t)input;
    decoder->stream.avail_in = available_in;
    decoder->stream.next_out = (char *)output;
    decoder->stream.avail_out = available_out;
    int result = BZ2_bzDecompress(&decoder->stream);
    *input_size = available_in - decoder->stream.avail_in;
    *output_size = available_out - decoder->stream.avail_out;
    decoder->stream.next_in = NULL;
    decoder->stream.next_out = NULL;
    switch (result) {
        case BZ_OK: return PREVIEW_BZIP2_OK;
        case BZ_STREAM_END: return PREVIEW_BZIP2_STREAM_END;
        case BZ_DATA_ERROR:
        case BZ_DATA_ERROR_MAGIC: return PREVIEW_BZIP2_DATA_ERROR;
        case BZ_MEM_ERROR: return PREVIEW_BZIP2_MEMORY_ERROR;
        default: return PREVIEW_BZIP2_FAILURE;
    }
}

void preview_bzip2_destroy(preview_bzip2_decoder *decoder) {
    if (decoder == NULL) return;
    BZ2_bzDecompressEnd(&decoder->stream);
    free(decoder);
}
