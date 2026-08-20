import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final platform = code.targetOS.name;
    final variant = switch (code.targetOS) {
      OS.android => switch (code.targetArchitecture.name) {
        'arm' => 'armeabi-v7a',
        'arm64' => 'arm64-v8a',
        'x64' => 'x86_64',
        final architecture => architecture,
      },
      OS.iOS =>
        '${code.iOS.targetSdk.type}-${code.targetArchitecture.name}',
      OS.macOS => code.targetArchitecture.name,
      _ => code.targetArchitecture.name,
    };
    final extension = switch (code.targetOS) {
      OS.windows => 'dll',
      OS.macOS || OS.iOS => 'dylib',
      _ => 'so',
    };

    for (final library in const [
      (asset: 'shared/widgets/blurhash_image.dart', file: 'lightnovel_native'),
      (asset: 'features/reader/woff2.dart', file: 'woff2'),
    ]) {
      final prefix = code.targetOS == OS.windows ? '' : 'lib';
      final file = input.packageRoot.resolve(
        'native/prebuilt/$platform/$variant/'
        '$prefix${library.file}.$extension',
      );
      if (!File.fromUri(file).existsSync()) {
        throw StateError(
          'Missing Native Asset for $platform/$variant: ${file.toFilePath()}',
        );
      }
      output.dependencies.add(file);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: library.asset,
          linkMode: DynamicLoadingBundled(),
          file: file,
        ),
      );
    }
  });
}
