import 'package:flutter_test/flutter_test.dart';
import 'package:swiftreceipt/services/sms_parser.dart';

void main() {
  group('SmsParser', () {
    test('parses standard Telebirr 127 SMS', () {
      const sms = 'You have received 250.00 ETB from ABEBE KEBEDE (251911223344). Transaction number is CI87X12345. Current balance is 1250.00 ETB.';
      final res = SmsParser.parse(sender: '127', body: sms);
      expect(res, isNotNull);
      expect(res!.provider, 'Telebirr');
      expect(res.reference, 'CI87X12345');
      expect(res.amount, 250.0);
      expect(res.senderName, 'ABEBE KEBEDE');
    });

    test('parses Telebirr with alternative formatting', () {
      const sms = 'Dear Customer, you have received ETB 1,500.00 from ALMAZ AYANA on 12/10/2026. transaction number: DIO23G4GOE.';
      final res = SmsParser.parse(sender: 'telebirr', body: sms);
      expect(res, isNotNull);
      expect(res!.reference, 'DIO23G4GOE');
      expect(res.amount, 1500.0);
      expect(res.senderName, 'ALMAZ AYANA');
    });

    test('parses CBE credit notification with FT reference', () {
      const sms = 'Your account 100012345678 was credited with ETB 750.50 by KEBEDE TESEMA. Txn ID: FT26848201. Your balance is ETB 15,200.00.';
      final res = SmsParser.parse(sender: 'CBE', body: sms);
      expect(res, isNotNull);
      expect(res!.provider, 'CBE');
      expect(res.reference, 'FT26848201');
      expect(res.amount, 750.50);
      expect(res.senderName, 'KEBEDE TESEMA');
    });

    test('ignores OTP, verification codes and noise', () {
      const otp1 = 'Your Telebirr verification code is 492012. Do not share this code.';
      final res1 = SmsParser.parse(sender: '127', body: otp1);
      expect(res1, isNull);

      const otp2 = 'Dear customer, your OTP is 894123 for mobile banking login.';
      final res2 = SmsParser.parse(sender: 'CBE', body: otp2);
      expect(res2, isNull);

      const promo = 'Recharge your account now and get 100% weekend bonus data!';
      final res3 = SmsParser.parse(sender: '127', body: promo);
      expect(res3, isNull);
    });

    test('parses other Ethiopian banks e.g. Awash', () {
      const sms = 'Dear Customer, your account was credited with ETB 300.00. Ref No: AW20261012999. Thank you for banking with Awash.';
      final res = SmsParser.parse(sender: 'AWASH_BANK', body: sms);
      expect(res, isNotNull);
      expect(res!.provider, 'Awash');
      expect(res.amount, 300.0);
      expect(res.reference, 'AW20261012999');
    });
  });
}
