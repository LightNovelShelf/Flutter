import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/widgets/fade_clamp_box.dart';
import '../../../shared/widgets/html_content.dart';
import 'book_introduction_sheet.dart';

/// 详情页简介：折叠到五行的像素预算，超出部分渐隐并给出「展开」。
class BookIntroduction extends StatefulWidget {
  const BookIntroduction({super.key, required this.detail});

  final BookDetail detail;

  @override
  State<BookIntroduction> createState() => _BookIntroductionState();
}

class _BookIntroductionState extends State<BookIntroduction> {
  static const int _collapsedLines = 5;

  double? _contentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lineExtent = HtmlContent.compactLineExtentOf(context);
    final collapsedHeight = lineExtent * _collapsedLines;
    final height = _contentHeight;
    final clamped = height != null && height > collapsedHeight + 0.5;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '简介',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          FadeClampBox(
            maxHeight: collapsedHeight,
            // 渐变只盖末行下半，末行本身仍可读。
            fadeExtent: lineExtent * 0.7,
            onMeasured: _onMeasured,
            child: HtmlContentTheme.merge(
              data: HtmlContentThemeData(
                textStyle: TextStyle(color: colors.onSurfaceVariant),
              ),
              child: HtmlContent.compact(html: widget.detail.introduction),
            ),
          ),
          if (clamped)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    showBookIntroductionSheet(context, widget.detail),
                child: const Text('展开'),
              ),
            ),
        ],
      ),
    );
  }

  void _onMeasured(double height) {
    if (!mounted || _contentHeight == height) return;
    setState(() => _contentHeight = height);
  }
}
