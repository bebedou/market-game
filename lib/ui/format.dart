String money(int cents, {bool signed = false}) {
  final value = cents.abs();
  final dollars = (value ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  final sign = cents < 0
      ? '−'
      : signed && cents > 0
      ? '+'
      : '';
  return '$sign\$$dollars.${(value % 100).toString().padLeft(2, '0')}';
}

String count(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);
