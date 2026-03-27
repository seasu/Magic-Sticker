import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cat_loading_widget.dart';

/// Pro Loading 薄包裝。
///
/// 所有動畫邏輯由 [CatLoadingWidget] 統一處理；
/// 本 widget 只負責傳入金香檳配色 + 漸層背景 + Pro 專屬標題 / 描述卡。
class ProCustomLoadingWidget extends StatelessWidget {
  final String? emotionDesc;
  final String? styleDesc;

  const ProCustomLoadingWidget({
    super.key,
    this.emotionDesc,
    this.styleDesc,
  });

  @override
  Widget build(BuildContext context) {
    final title = emotionDesc != null
        ? 'AI 正在詮釋您的專屬情緒'
        : 'AI 正在生成您的專屬貼圖';

    return CatLoadingWidget(
      title:              title,
      subtitle:           '正在創作 · 約 15~25 秒',
      colors:             CatColorScheme.proChampagne,
      catPositionRatio:   0.48,
      backgroundGradient: const LinearGradient(
        colors: [Color(0xFFFAFAF5), Color(0xFFF5EDD8)],
        begin:  Alignment.topCenter,
        end:    Alignment.bottomCenter,
      ),
      systemUiStyle: const SystemUiOverlayStyle(
        statusBarColor:                    Color(0xFFFAFAF5),
        statusBarIconBrightness:           Brightness.dark,
        statusBarBrightness:               Brightness.light,
        systemNavigationBarColor:          Color(0xFFF5EDD8),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }
}
