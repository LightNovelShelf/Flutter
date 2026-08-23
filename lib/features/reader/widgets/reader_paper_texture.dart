import 'package:flutter/material.dart';

/// 纸质背景的纸纹，与 Web 端阅读器共用同一组贴图，按明暗各一张，原尺寸平铺。
class ReaderPaperTexture extends StatelessWidget {
  const ReaderPaperTexture({super.key});

  static const AssetImage _light = AssetImage('assets/img/bg-paper.jpg');
  static const AssetImage _dark = AssetImage('assets/img/bg-paper-dark.jpeg');

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      image: DecorationImage(
        image: Theme.of(context).brightness == Brightness.dark ? _dark : _light,
        repeat: ImageRepeat.repeat,
      ),
    ),
    child: const SizedBox.expand(),
  );
}
