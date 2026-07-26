// Generates Android/iOS launcher icons from assets/branding/app_logo.png
// Run: dart run tool/generate_app_icons.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final root = Directory.current;
  final srcPath = File('${root.path}/assets/branding/app_logo.png');
  if (!srcPath.existsSync()) {
    stderr.writeln('Missing ${srcPath.path}');
    exit(1);
  }

  final decoded = img.decodeImage(srcPath.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Failed to decode logo');
    exit(1);
  }

  // Tighten crop around non-black content, then pad for safe icon margins.
  final cropped = _cropContent(decoded, threshold: 18);
  final master = _fitOnSquare(cropped, size: 1024, paddingRatio: 0.10);

  // Master assets: square launcher source + horizontal wordmark for in-app.
  File('${root.path}/assets/branding/app_icon_1024.png')
      .writeAsBytesSync(img.encodePng(master));
  File('${root.path}/assets/branding/app_wordmark.png')
      .writeAsBytesSync(img.encodePng(cropped));

  // Android mipmaps
  final androidSizes = <String, int>{
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final e in androidSizes.entries) {
    final out = File(
      '${root.path}/android/app/src/main/res/${e.key}/ic_launcher.png',
    );
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(
      img.encodePng(img.copyResize(
        master,
        width: e.value,
        height: e.value,
        interpolation: img.Interpolation.average,
      )),
    );
    stdout.writeln('Android ${e.key}/ic_launcher.png (${e.value}px)');
  }

  // iOS AppIcon set
  final iosDir =
      Directory('${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset');
  iosDir.createSync(recursive: true);
  final iosSpecs = <(String, int)>[
    ('Icon-App-20x20@1x.png', 20),
    ('Icon-App-20x20@2x.png', 40),
    ('Icon-App-20x20@3x.png', 60),
    ('Icon-App-29x29@1x.png', 29),
    ('Icon-App-29x29@2x.png', 58),
    ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40),
    ('Icon-App-40x40@2x.png', 80),
    ('Icon-App-40x40@3x.png', 120),
    ('Icon-App-60x60@2x.png', 120),
    ('Icon-App-60x60@3x.png', 180),
    ('Icon-App-76x76@1x.png', 76),
    ('Icon-App-76x76@2x.png', 152),
    ('Icon-App-83.5x83.5@2x.png', 167),
    ('Icon-App-1024x1024@1x.png', 1024),
  ];
  for (final (name, size) in iosSpecs) {
    final out = File('${iosDir.path}/$name');
    out.writeAsBytesSync(
      img.encodePng(img.copyResize(
        master,
        width: size,
        height: size,
        interpolation: img.Interpolation.average,
      )),
    );
    stdout.writeln('iOS $name (${size}px)');
  }

  stdout.writeln('Done.');
}

img.Image _cropContent(img.Image src, {required int threshold}) {
  var minX = src.width;
  var minY = src.height;
  var maxX = 0;
  var maxY = 0;

  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final lum = (p.r + p.g + p.b) / 3;
      if (lum > threshold) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX <= minX || maxY <= minY) return src;

  // Small bleed so anti-aliased edges aren't clipped.
  const bleed = 4;
  minX = math.max(0, minX - bleed);
  minY = math.max(0, minY - bleed);
  maxX = math.min(src.width - 1, maxX + bleed);
  maxY = math.min(src.height - 1, maxY + bleed);

  return img.copyCrop(
    src,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
}

img.Image _fitOnSquare(
  img.Image content, {
  required int size,
  required double paddingRatio,
}) {
  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

  final inner = (size * (1 - paddingRatio * 2)).round();
  final scale = math.min(
    inner / content.width,
    inner / content.height,
  );
  final w = math.max(1, (content.width * scale).round());
  final h = math.max(1, (content.height * scale).round());
  final resized = img.copyResize(
    content,
    width: w,
    height: h,
    interpolation: img.Interpolation.average,
  );

  final dx = ((size - w) / 2).round();
  final dy = ((size - h) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  return canvas;
}
