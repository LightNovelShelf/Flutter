#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

#if defined(_WIN32)
#define LN_EXPORT extern "C" __declspec(dllexport)
#else
#define LN_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {

constexpr int kMaxDimension = 512;
constexpr int kMaxComponents = 9;

constexpr std::array<int8_t, 128> kBase83 = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, 62, 63, 64, -1, -1, -1, -1, 65, 66, 67, 68, 69, -1,
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 70, 71, -1, 72, -1, 73,
    74, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 75, -1, 76, 77, 78,
    -1, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
    51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 79, 80, 81, 82, -1,
};

struct Color {
  float red;
  float green;
  float blue;
};

int Decode83(const char* value, size_t offset, size_t length) {
  int result = 0;
  for (size_t index = 0; index < length; ++index) {
    const auto character = static_cast<uint8_t>(value[offset + index]);
    if (character >= kBase83.size() || kBase83[character] < 0) return -1;
    result = result * 83 + kBase83[character];
  }
  return result;
}

float SrgbToLinear(int value) {
  const float normalized = static_cast<float>(value) / 255.0f;
  return normalized <= 0.04045f
      ? normalized / 12.92f
      : std::pow((normalized + 0.055f) / 1.055f, 2.4f);
}

const std::array<uint8_t, 4097>& LinearToSrgbTable() {
  static const auto table = [] {
    std::array<uint8_t, 4097> result{};
    for (size_t index = 0; index < result.size(); ++index) {
      const float linear = static_cast<float>(index) / 4096.0f;
      const float srgb = linear <= 0.0031308f
          ? linear * 12.92f
          : 1.055f * std::pow(linear, 1.0f / 2.4f) - 0.055f;
      result[index] = static_cast<uint8_t>(srgb * 255.0f + 0.5f);
    }
    return result;
  }();
  return table;
}

uint8_t LinearToSrgb(float value) {
  if (value <= 0.0f) return 0;
  if (value >= 1.0f) return 255;
  const auto index = static_cast<size_t>(value * 4096.0f + 0.5f);
  return LinearToSrgbTable()[index];
}

float SignedPow(float value, float exponent) {
  return std::copysign(std::pow(std::abs(value), exponent), value);
}

}  // namespace

// Returns 0 on success, 1 for an invalid hash, 2 for invalid dimensions, and
// 3 when the output buffer is too small. Output pixels are RGBA8888.
LN_EXPORT int32_t ln_blurhash_decode(const char* hash,
                                     size_t hash_length,
                                     uint32_t width,
                                     uint32_t height,
                                     uint8_t* output,
                                     size_t output_length) {
  if (hash == nullptr || output == nullptr || hash_length < 6) return 1;
  if (width == 0 || height == 0 || width > kMaxDimension ||
      height > kMaxDimension) {
    return 2;
  }
  const size_t required_length = static_cast<size_t>(width) * height * 4;
  if (output_length < required_length) return 3;

  const int size_flag = Decode83(hash, 0, 1);
  if (size_flag < 0) return 1;
  const int components_x = size_flag % 9 + 1;
  const int components_y = size_flag / 9 + 1;
  const int component_count = components_x * components_y;
  if (hash_length != static_cast<size_t>(4 + component_count * 2)) return 1;

  const int quantized_maximum = Decode83(hash, 1, 1);
  const int dc = Decode83(hash, 2, 4);
  if (quantized_maximum < 0 || dc < 0) return 1;

  std::array<Color, kMaxComponents * kMaxComponents> colors{};
  colors[0] = {
      SrgbToLinear(dc >> 16),
      SrgbToLinear((dc >> 8) & 255),
      SrgbToLinear(dc & 255),
  };
  const float maximum = static_cast<float>(quantized_maximum + 1) / 166.0f;
  for (int index = 1; index < component_count; ++index) {
    const int ac = Decode83(hash, 4 + index * 2, 2);
    if (ac < 0) return 1;
    const int red = ac / (19 * 19);
    const int green = (ac / 19) % 19;
    const int blue = ac % 19;
    colors[index] = {
        SignedPow((red - 9) / 9.0f, 2.0f) * maximum,
        SignedPow((green - 9) / 9.0f, 2.0f) * maximum,
        SignedPow((blue - 9) / 9.0f, 2.0f) * maximum,
    };
  }

  // Cosine values are invariant for every pixel row/column. Computing these
  // compact tables once removes cos() from the hot component summation loop.
  std::array<float, kMaxComponents * kMaxDimension> cosine_x{};
  std::array<float, kMaxComponents * kMaxDimension> cosine_y{};
  constexpr float kPi = 3.14159265358979323846f;
  for (int component = 0; component < components_x; ++component) {
    for (uint32_t x = 0; x < width; ++x) {
      cosine_x[component * kMaxDimension + x] =
          std::cos(kPi * x * component / width);
    }
  }
  for (int component = 0; component < components_y; ++component) {
    for (uint32_t y = 0; y < height; ++y) {
      cosine_y[component * kMaxDimension + y] =
          std::cos(kPi * y * component / height);
    }
  }

  size_t pixel = 0;
  for (uint32_t y = 0; y < height; ++y) {
    for (uint32_t x = 0; x < width; ++x) {
      float red = 0.0f;
      float green = 0.0f;
      float blue = 0.0f;
      for (int component_y = 0; component_y < components_y; ++component_y) {
        const float basis_y = cosine_y[component_y * kMaxDimension + y];
        for (int component_x = 0; component_x < components_x; ++component_x) {
          const float basis =
              cosine_x[component_x * kMaxDimension + x] * basis_y;
          const Color& color = colors[component_x + component_y * components_x];
          red += color.red * basis;
          green += color.green * basis;
          blue += color.blue * basis;
        }
      }
      output[pixel++] = LinearToSrgb(red);
      output[pixel++] = LinearToSrgb(green);
      output[pixel++] = LinearToSrgb(blue);
      output[pixel++] = 255;
    }
  }
  return 0;
}
