import 'package:flutter/material.dart';

import '../../../shared/widgets/skeleton.dart';

/// 详情页首屏骨架：封面 + 标题 + 统计条 + 主按钮 + 简介 + 更新条。
class BookDetailSkeleton extends StatelessWidget {
  const BookDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              SkeletonBox(height: 150, width: 100),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(height: 28, widthFactor: 0.88),
                    SizedBox(height: 9),
                    SkeletonBox(height: 15, widthFactor: 0.42),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Row(
            children: <Widget>[
              SkeletonBox(height: 26, width: 58),
              SizedBox(width: 8),
              SkeletonBox(height: 26, width: 58),
              SizedBox(width: 8),
              SkeletonBox(height: 26, width: 92),
            ],
          ),
          SizedBox(height: 20),
          SkeletonBox(height: 56, widthFactor: 1, radius: 16),
          SizedBox(height: 20),
          SkeletonBox(height: 88, widthFactor: 1),
          SizedBox(height: 20),
          SkeletonBox(height: 42, widthFactor: 1, radius: 12),
        ],
      ),
    ),
  );
}
