import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:zxing2/qrcode.dart';

final _logger = Logger('QrImageDecoder');

/// Decodes a QR code from raw image bytes (e.g. a screenshot or a photo of
/// a printed code).
///
/// Uses `zxing2`, a pure-Dart QR decoder, so it works on every platform
/// Aika supports (including Windows and Linux, where no live camera
/// scanning library is currently available for Flutter).
///
/// Returns `null` if [bytes] could not be decoded as an image, or if no QR
/// code could be found in it.
String? decodeQrFromImageBytes(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    return null;
  }

  try {
    final source = RGBLuminanceSource(
      image.width,
      image.height,
      image.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
    );
    final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
    final result = QRCodeReader().decode(bitmap);
    return result.text;
  } catch (e) {
    // Thrown by zxing2 (e.g. `ReaderException`) when no QR code is found,
    // or by the conversion above for unusable images. Both are expected
    // "not found" outcomes from the caller's point of view.
    _logger.fine('Could not decode QR code from image: $e');
    return null;
  }
}

/// Lets the user pick an image file (screenshot, saved photo, ...) and
/// tries to decode a QR code from it.
///
/// This is the primary way to use "Scanner un QR Code" on platforms without
/// live camera scanning support (Windows, Linux), and a convenient fallback
/// everywhere else (e.g. a code received as an image in a chat app).
///
/// Returns the decoded text, or `null` if the user cancelled or no QR code
/// was found.
Future<String?> pickAndDecodeQrFromImage() async {
  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
  );

  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) {
    return null;
  }

  final bytes = await file.readAsBytes();
  return decodeQrFromImageBytes(bytes);
}
