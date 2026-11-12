import 'dart:convert';
import 'dart:typed_data';

import '../core/safe_int.dart';

/// Writes the canonical binary form of engine state.
///
/// Save files and the state hash both come from this one encoding, so they
/// can't disagree. Integers are variable-length: the first byte holds a
/// continuation bit, a sign bit and 6 bits of magnitude; each further byte a
/// continuation bit and 7 more bits. Only `%` and `~/` are used, so values up
/// to 2^53 encode identically on every platform.
final class StateWriter {
  final _bytes = <int>[];

  void writeInt(int value) {
    assert(isSafeInt(value), '$value is outside the safe integer range');
    var magnitude = value.abs();
    var byte = (value < 0 ? 0x40 : 0) | (magnitude % 0x40);
    magnitude = magnitude ~/ 0x40;
    while (magnitude > 0) {
      _bytes.add(byte | 0x80);
      byte = magnitude % 0x80;
      magnitude = magnitude ~/ 0x80;
    }
    _bytes.add(byte);
  }

  void writeBool(bool value) => writeInt(value ? 1 : 0);

  void writeNullableInt(int? value) {
    writeBool(value != null);
    if (value != null) writeInt(value);
  }

  void writeString(String value) {
    final encoded = utf8.encode(value);
    writeInt(encoded.length);
    _bytes.addAll(encoded);
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

/// The newest layout of saved state. Bump it whenever the layout or the
/// simulation rules change, and have readers of older layouts fill in what
/// they lack: see [StateReader.version].
const int currentStateVersion = 27;

/// Reads what [StateWriter] wrote. Malformed or truncated data throws a
/// [FormatException].
final class StateReader {
  StateReader(this._bytes, {this.version = currentStateVersion});

  /// The layout version being read. Readers check it for fields added after
  /// it and use defaults for them.
  int version;

  final Uint8List _bytes;
  int _position = 0;

  int readInt() {
    var byte = _nextByte();
    final negative = (byte & 0x40) != 0;
    var magnitude = byte & 0x3F;
    var factor = 0x40;
    for (var count = 0; (byte & 0x80) != 0; count++) {
      if (count == 8) throw const FormatException('Integer is too long');
      byte = _nextByte();
      magnitude += (byte & 0x7F) * factor;
      factor *= 0x80;
    }
    if (!isSafeInt(magnitude)) {
      throw const FormatException('Integer is outside the safe range');
    }
    return negative ? -magnitude : magnitude;
  }

  bool readBool() => switch (readInt()) {
    0 => false,
    1 => true,
    final value => throw FormatException('Expected a bool, got $value'),
  };

  int? readNullableInt() => readBool() ? readInt() : null;

  String readString() {
    final length = readInt();
    if (length < 0 || length > _bytes.length - _position) {
      throw const FormatException('String runs past the end of the data');
    }
    final text = utf8.decode(
      Uint8List.sublistView(_bytes, _position, _position + length),
    );
    _position += length;
    return text;
  }

  void expectEnd() {
    if (_position != _bytes.length) {
      throw const FormatException('Unexpected data after the end');
    }
  }

  int _nextByte() {
    if (_position >= _bytes.length) {
      throw const FormatException('Unexpected end of data');
    }
    return _bytes[_position++];
  }
}
