import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _FinalSizeNative = Size Function(Pointer<Uint8>, Size);
typedef _DecodeNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Pointer<Size>,
);

@Native<_FinalSizeNative>(
  assetId: 'package:lightnovel/features/reader/woff2.dart',
  symbol: 'ln_woff2_final_size',
)
external int _finalSize(Pointer<Uint8> input, int inputLength);

@Native<_DecodeNative>(
  assetId: 'package:lightnovel/features/reader/woff2.dart',
  symbol: 'ln_woff2_decode',
)
external int _decode(
  Pointer<Uint8> input,
  int inputLength,
  Pointer<Uint8> output,
  int outputCapacity,
  Pointer<Size> outputLength,
);

Uint8List decodeWoff2(Uint8List input) {
  if (input.length < 4 ||
      input[0] != 0x77 ||
      input[1] != 0x4f ||
      input[2] != 0x46 ||
      input[3] != 0x32) {
    throw const FormatException('Input is not a WOFF2 font.');
  }

  final nativeInput = calloc<Uint8>(input.length);
  Pointer<Uint8>? nativeOutput;
  final outputLength = calloc<Size>();
  try {
    nativeInput.asTypedList(input.length).setAll(0, input);
    final capacity = _finalSize(nativeInput, input.length);
    if (capacity <= 0 || capacity > 128 * 1024 * 1024) {
      throw const FormatException('Invalid or oversized WOFF2 font.');
    }

    nativeOutput = calloc<Uint8>(capacity);
    final result = _decode(
      nativeInput,
      input.length,
      nativeOutput,
      capacity,
      outputLength,
    );
    if (result != 0 ||
        outputLength.value <= 0 ||
        outputLength.value > capacity) {
      throw FormatException('libwoff2 decode failed ($result).');
    }
    return Uint8List.fromList(nativeOutput.asTypedList(outputLength.value));
  } finally {
    if (nativeOutput != null) calloc.free(nativeOutput);
    calloc.free(outputLength);
    calloc.free(nativeInput);
  }
}
