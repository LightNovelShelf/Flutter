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

  /// 同步完成：解码后录成每像素一个色块的 Picture，`toImageSync` 立即拿到 GPU 图像。
  /// 占位层因此在挂载的第一帧就有内容，不会先闪一帧纯色底。
  @override
  ImageStreamCompleter loadImage(
    BlurHashImage key,
    ImageDecoderCallback decode,
  ) {
    final Future<ImageInfo> info;
    try {
      info = SynchronousFuture<ImageInfo>(_rasterize());
    } catch (error, stackTrace) {
      return OneFrameImageStreamCompleter(
        Future<ImageInfo>.error(error, stackTrace),
      );
    }
    return OneFrameImageStreamCompleter(info);
  }

  ImageInfo _rasterize() {
    final pixels = (debugBlurHashPixelDecoder ?? decodeBlurHash)(
      blurHash,
      width: decodingWidth,
      height: decodingHeight,
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..isAntiAlias = false;
    var offset = 0;
    for (var y = 0; y < decodingHeight; y++) {
      for (var x = 0; x < decodingWidth; x++) {
        paint.color = ui.Color.fromARGB(
          pixels[offset + 3],
          pixels[offset],
          pixels[offset + 1],
          pixels[offset + 2],
        );
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          paint,
        );
        offset += 4;
      }
    }
    final picture = recorder.endRecording();
    try {
      return ImageInfo(
        image: picture.toImageSync(decodingWidth, decodingHeight),
        scale: scale,
      );
    } finally {
      picture.dispose();
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
