import 'dart:io';
import 'dart:typed_data';

/// Duration of a PCM WAV file from its header (Android TTS writes WAV), or
/// null if the file is not a readable WAV. Lets prefetched chunks contribute
/// their real length to the timeline before they are played.
double? wavDurationSeconds(File file) {
  RandomAccessFile? raf;
  try {
    raf = file.openSync();
    final header = raf.readSync(4096);
    if (header.length < 44) return null;
    final b = ByteData.sublistView(header);
    String tag(int at) => String.fromCharCodes(header.sublist(at, at + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
    int? byteRate;
    var pos = 12;
    while (pos + 8 <= header.length) {
      final id = tag(pos);
      final size = b.getUint32(pos + 4, Endian.little);
      if (id == 'fmt ' && pos + 16 <= header.length) {
        byteRate = b.getUint32(pos + 8 + 8, Endian.little);
      } else if (id == 'data') {
        // Some writers leave the size unset while streaming; fall back to the file length.
        final dataBytes = (size == 0 || size == 0xFFFFFFFF) ? file.lengthSync() - pos - 8 : size;
        if (byteRate == null || byteRate == 0 || dataBytes <= 0) return null;
        return dataBytes / byteRate;
      }
      pos += 8 + size + (size.isOdd ? 1 : 0);
    }
    return null;
  } on FileSystemException {
    return null;
  } finally {
    raf?.closeSync();
  }
}
