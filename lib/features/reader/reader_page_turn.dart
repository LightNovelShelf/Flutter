import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/settings/app_settings.dart';

const Duration readerPageTurnDuration = Duration(milliseconds: 220);

/// 按阅读设置切换到目标页。
void turnReaderPage(
  PageController controller,
  int page,
  ReaderPageTurnAnimation animation,
) {
  switch (animation) {
    case ReaderPageTurnAnimation.none:
      controller.jumpToPage(page);
    case ReaderPageTurnAnimation.slide:
      unawaited(
        controller.animateToPage(
          page,
          duration: readerPageTurnDuration,
          curve: Curves.easeOutCubic,
        ),
      );
  }
}
