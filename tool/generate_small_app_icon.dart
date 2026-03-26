import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = File('assets/app_icon.png');
  final target = File('assets/images/app_icon_small.png');

  if (!source.existsSync()) {
    stderr.writeln('❌ Source icon not found: ${source.path}');
    exit(1);
  }

  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('❌ Failed to decode image: ${source.path}');
    exit(1);
  }

  final resized = img.copyResize(decoded, width: 128, height: 128);
  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(img.encodePng(resized));

  stdout.writeln('✅ app_icon_small.png created: ${resized.width}x${resized.height}');
}
