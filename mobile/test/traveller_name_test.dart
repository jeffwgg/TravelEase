import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/core/traveller_name.dart';

void main() {
  test('supports international names, spaces, hyphens and apostrophes', () {
    for (final name in [
      'Yan Thong',
      "Anne-Marie O'Neil",
      'D’Arcy',
      'José',
      '王小明',
      'नमिता',
    ]) {
      expect(TravellerName.validate(name), isNull, reason: name);
    }
  });
  test('rejects digits and other invalid input before submission', () {
    expect(TravellerName.validate('Jeff123'), 'Name must not contain numbers.');
    expect(TravellerName.validate('Name١'), 'Name must not contain numbers.');
    for (final name in ['', '   ', "--'", 'Name@', 'Name🙂']) {
      expect(TravellerName.validate(name), isNotNull);
    }
  });
  test(
    'filters pasted numbers and symbols while keeping allowed characters',
    () {
      final result = TravellerName.formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: "Yan123 O'Neil-王!",
          selection: TextSelection.collapsed(offset: 15),
        ),
      );
      expect(result.text, "Yan O'Neil-王");
    },
  );
}
