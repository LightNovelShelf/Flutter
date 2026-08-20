import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

typedef _DecodeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Uint32,
  ffi.Uint32,
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
);
@ffi.Native<_DecodeNative>(
  assetId: 'package:lightnovel/shared/widgets/blurhash_image.dart',
  symbol: 'ln_blurhash_decode',
)
external int _decode(
  ffi.Pointer<ffi.Uint8> hash,
  int hashLength,
  int width,
  int height,
  ffi.Pointer<ffi.Uint8> output,
  int outputLength,
);

typedef BlurHashPixelDecoder = Uint8List Function(
  String hash, {
  required int width,
  required int height,
});

@visibleForTesting
BlurHashPixelDecoder? debugBlurHashPixelDecoder;

Uint8List decodeBlurHash(
  String hash, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0 || width > 512 || height > 512) {
    throw RangeError('BlurHash dimensions must be between 1 and 512.');
  }
  final hashBytes = Uint8List.fromList(hash.codeUnits);
  if (hashBytes.any((value) => value > 0x7f)) {
    throw const FormatException(
      'BlurHash must contain only ASCII Base83 data.',
    );
  }

  final outputLength = width * height * 4;
  final nativeHash = calloc<ffi.Uint8>(hashBytes.length);
  final nativeOutput = calloc<ffi.Uint8>(outputLength);
  try {
    nativeHash.asTypedList(hashBytes.length).setAll(0, hashBytes);
    final result = _decode(
      nativeHash,
      hashBytes.length,
      width,
      height,
      nativeOutput,
      outputLength,
    );
    if (result == 1) throw const FormatException('Invalid BlurHash.');
    if (result == 2) throw RangeError('Invalid BlurHash dimensions.');
    if (result != 0) throw StateError('BlurHash decode failed ($result).');
    return Uint8List.fromList(nativeOutput.asTypedList(outputLength));
  } finally {
    calloc.free(nativeOutput);
    calloc.free(nativeHash);
  }
}

@immutable
final class BlurHashImage extends ImageProvider<BlurHashImage> {
  const BlurHashImage(
    this.blurHash, {
    required this.decodingWidth,
    required this.decodingHeight,
    this.scale = 1,
  });

  final String blurHash;
  final int decodingWidth;
  final int decodingHeight;
  final double scale;

  @override
  Future<BlurHashImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    BlurHashImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final pixels = (debugBlurHashPixelDecoder ?? decodeBlurHash)(
      blurHash,
      width: decodingWidth,
      height: decodingHeight,
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: decodingWidth,
      height: decodingHeight,
      rowBytes: decodingWidth * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      return ImageInfo(image: frame.image, scale: scale);
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BlurHashImage &&
      other.blurHash == blurHash &&
      other.decodingWidth == decodingWidth &&
      other.decodingHeight == decodingHeight &&
      other.scale == scale;

  @override
  int get hashCode =>
      Object.hash(blurHash, decodingWidth, decodingHeight, scale);
}
