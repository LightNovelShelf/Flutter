#include <cstddef>
#include <cstdint>

#include <woff2/decode.h>
#include <woff2/output.h>

#if defined(_WIN32)
#define LN_EXPORT extern "C" __declspec(dllexport)
#else
#define LN_EXPORT extern "C" __attribute__((visibility("default")))
#endif

LN_EXPORT size_t ln_woff2_final_size(const uint8_t* input, size_t input_length) {
  if (input == nullptr || input_length < 4) return 0;
  return woff2::ComputeWOFF2FinalSize(input, input_length);
}

LN_EXPORT int32_t ln_woff2_decode(const uint8_t* input,
                                  size_t input_length,
                                  uint8_t* output,
                                  size_t output_capacity,
                                  size_t* output_length) {
  if (input == nullptr || output == nullptr || output_length == nullptr) return 1;
  woff2::WOFF2MemoryOut writer(output, output_capacity);
  if (!woff2::ConvertWOFF2ToTTF(input, input_length, &writer)) return 2;
  *output_length = writer.Size();
  return 0;
}
