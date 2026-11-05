import 'dart:typed_data';

import 'package:engine/src/core/safe_int.dart';
import 'package:engine/src/persistence/state_io.dart';
import 'package:test/test.dart';

List<int> encodeInt(int value) => (StateWriter()..writeInt(value)).toBytes();

void main() {
  test('encodes integers with the documented byte layout', () {
    expect(encodeInt(0), [0x00]);
    expect(encodeInt(-1), [0x41]);
    expect(encodeInt(63), [0x3F]);
    expect(encodeInt(64), [0x80, 0x01]);
    expect(encodeInt(-64), [0xC0, 0x01]);
    expect(encodeInt(maxSafeInt), [
      0xBF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, //
    ]);
  });

  test('round-trips integers, bools and strings', () {
    const ints = [
      0, 1, -1, 63, 64, -64, 127, 128, 8191, 8192, 4294967295, 4294967296, //
      -4294967296, 123456789012345, maxSafeInt, -maxSafeInt,
    ];
    final writer = StateWriter();
    ints.forEach(writer.writeInt);
    writer
      ..writeBool(true)
      ..writeBool(false)
      ..writeString('')
      ..writeString('Café — 東京 🚀');
    final reader = StateReader(writer.toBytes());
    expect([for (final _ in ints) reader.readInt()], ints);
    expect(reader.readBool(), isTrue);
    expect(reader.readBool(), isFalse);
    expect(reader.readString(), '');
    expect(reader.readString(), 'Café — 東京 🚀');
    reader.expectEnd();
  });

  test('rejects malformed data', () {
    StateReader reader(List<int> bytes) =>
        StateReader(Uint8List.fromList(bytes));
    expect(() => reader([]).readInt(), throwsFormatException);
    expect(() => reader([0x80]).readInt(), throwsFormatException);
    expect(
      () => reader(List.filled(10, 0xFF)).readInt(),
      throwsFormatException,
    );
    expect(() => reader([0x02]).readBool(), throwsFormatException);
    expect(() => reader([0x05, 0x61]).readString(), throwsFormatException);
    expect(
      () => (reader([0x00, 0x00])..readInt()).expectEnd(),
      throwsFormatException,
    );
  });
}
