import 'package:flutter_test/flutter_test.dart';
import 'package:swiftreceipt/services/ocr_parser.dart';

void main() {
  test('parses a Telebirr-style receipt', () {
    final r = OcrParser.parse('Telebirr\nTransaction Number: DAB1XY2Z3A\nTotal Paid Amount 1,250.00 Birr');
    expect(r.provider, 'Telebirr');
    expect(r.reference, 'DAB1XY2Z3A');
    expect(r.amount, 1250.0);
  });

  test('parses a CBE-style receipt', () {
    final r = OcrParser.parse('Commercial Bank of Ethiopia\nReference No: FT23456ABCDE\nTransferred Amount ETB 800.00');
    expect(r.provider, 'CBE');
    expect(r.reference, 'FT23456ABCDE');
    expect(r.amount, 800.0);
  });

  test('parses Telebirr transfer with standalone negative amount and sender', () {
    const raw = '''
Telebirr
Transfer to End User
-101.00
ETB
Transaction Number: DIO23G4GOE
Payer: Abebe Bikila
Receiver: Cafe Central
2026-10-12 11:52:14
''';
    final r = OcrParser.parse(raw);
    expect(r.provider, 'Telebirr');
    expect(r.reference, 'DIO23G4GOE');
    expect(r.amount, 101.0);
    expect(r.sender, 'Abebe Bikila');
    expect(r.receiver, 'Cafe Central');
  });

  test('parses multi-line sender name and standalone amount without ETB suffix', () {
    const raw = '''
Commercial Bank of Ethiopia
Completed
150.00
Transaction Ref: FT99887766A
Sender
Yoni Tesfaye
''';
    final r = OcrParser.parse(raw);
    expect(r.provider, 'CBE');
    expect(r.reference, 'FT99887766A');
    expect(r.amount, 150.0);
    expect(r.sender, 'Yoni Tesfaye');
  });
}
