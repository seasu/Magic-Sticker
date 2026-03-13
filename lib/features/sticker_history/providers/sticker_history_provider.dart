import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sticker_record.dart';
import '../services/sticker_archive_service.dart';

final stickerHistoryProvider =
    FutureProvider.autoDispose<List<StickerRecord>>((ref) async {
  return StickerArchiveService.instance.loadAll();
});
