import 'package:flutter/material.dart';

/// 單張貼圖文字編輯面板
///
/// 顯示目前頁貼圖的文字，使用者可直接修改；
/// 文字改變時即時回呼 [onTextChanged]。
class CaptionEditor extends StatefulWidget {
  final String text;
  final int stickerIndex; // 目前第幾張貼圖（0-based），用於顯示標題
  final ValueChanged<String> onTextChanged;

  const CaptionEditor({
    super.key,
    required this.text,
    required this.stickerIndex,
    required this.onTextChanged,
  });

  @override
  State<CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<CaptionEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(CaptionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 換頁或 AI 重新生成時同步文字
    if (widget.text != _controller.text) {
      _controller.text = widget.text;
      _controller.selection = TextSelection.collapsed(
        offset: widget.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '貼圖 ${widget.stickerIndex + 1} 文字',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 1,
            maxLength: 10,
            onChanged: widget.onTextChanged,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '輸入 2–6 字…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}
