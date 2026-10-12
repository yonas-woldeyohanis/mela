import 'sms_filters.dart';

/// High-precision parser for Ethiopian Bank & Mobile Money SMS notifications.
/// Parses Telebirr (127), CBE / CBE Birr, Awash, Dashen, Sinqee, BOA, etc.
class ParsedBankSms {
  const ParsedBankSms({
    required this.reference,
    required this.amount,
    required this.provider,
    this.senderName,
    this.receiverPhone,
    this.balance,
    required this.rawSms,
    required this.receivedAt,
  });

  final String reference;
  final double amount;
  final String provider; // 'Telebirr', 'CBE', 'Awash', 'Dashen', etc.
  final String? senderName;
  final String? receiverPhone;
  final double? balance;
  final String rawSms;
  final DateTime receivedAt;

  Map<String, dynamic> toMap() => {
        'reference': reference,
        'amount': amount,
        'provider': provider,
        'sender_name': senderName,
        'receiver_phone': receiverPhone,
        'balance': balance,
        'raw_sms': rawSms,
        'received_at': receivedAt.toIso8601String(),
      };
}

class SmsParser {
  // Number regex: 100, 100.00, 1,250.50
  static const _n = r'([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)';

  static double? _parseAmount(String? str) {
    if (str == null) return null;
    final cleaned = str.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  /// Evaluates an SMS text from a given sender and extracts payment details.
  /// Returns `null` if the SMS is NOT an incoming money payment (e.g. promo, OTP, debt, airtime purchase).
  static ParsedBankSms? parse({required String sender, required String body, DateTime? timestamp}) {
    // 1. Pass through master SMS filters (whitelist senders & blacklist noise)
    if (!SmsFilterConfig.shouldProcessSms(sender: sender, body: body)) {
      return null;
    }

    final text = body.replaceAll('\r', '').trim();
    final lower = text.toLowerCase();
    final senderUpper = sender.trim().toUpperCase();
    final time = timestamp ?? DateTime.now();

    // -------------------------------------------------------------
    // TELEBIRR (Sender usually "127", "telebirr", "EthioTelecom")
    // -------------------------------------------------------------
    if (senderUpper == '127' || senderUpper.contains('TELEBIRR') || lower.contains('telebirr') || lower.contains('ቴሌብር')) {
      // Must be incoming payment / deposit / received money
      // English: "You have received 500.00 ETB from ABEBE KEBEDE (251911******). Transaction number is CI87X12345."
      // English: "Dear Customer, you have received ETB 150.00 from ..."
      // Amharic: "ከ ABEBE KEBEDE (251911******) 500.00 ብር ደርሶዎታል:: የግብይት ቁጥር CI87X12345::"
      final isIncoming = lower.contains('received') ||
          lower.contains('ደርሶዎታል') ||
          lower.contains('ገቢ ተደርጓል') ||
          lower.contains('credited') ||
          lower.contains('transfer to end user');

      if (!isIncoming && !lower.contains('transaction number')) {
        return null;
      }

      // Reference
      String? ref;
      final refMatch = RegExp(r'(?:transaction\s*(?:number|no|id)|የግብይት\s*ቁጥር)\s*(?:is|:)?\s*([A-Za-z0-9]{8,16})', caseSensitive: false).firstMatch(text) ??
          RegExp(r'\b([A-Z0-9]{10})\b').firstMatch(text);
      if (refMatch != null) {
        ref = refMatch.group(1)?.trim().toUpperCase();
      }

      // Amount
      double? amt;
      final amtMatch = RegExp(r'(?:received|ደርሶዎታል|ገቢ)\s*(?:ETB|ብር)?\s*' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(r'(?:ETB|ብር|Birr)\s*' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(_n + r'\s*(?:ETB|ብር|birr)', caseSensitive: false).firstMatch(text);
      if (amtMatch != null) {
        amt = _parseAmount(amtMatch.group(1));
      }

      // Sender name: "from ABEBE KEBEDE (251...)" or "ከ ABEBE KEBEDE"
      String? senderName;
      final nameMatch = RegExp(r'(?:from|ከ)\s+([A-Za-z\s]+?)(?:\s*\(|\s+on|\s+at|\s*\.|\s+ደርሶዎታል|\s+trans)', caseSensitive: false).firstMatch(text);
      if (nameMatch != null) {
        senderName = nameMatch.group(1)?.trim();
      }

      if (ref != null && amt != null && amt > 0) {
        return ParsedBankSms(
          reference: ref,
          amount: amt,
          provider: 'Telebirr',
          senderName: senderName,
          rawSms: text,
          receivedAt: time,
        );
      }
    }

    // -------------------------------------------------------------
    // COMMERCIAL BANK OF ETHIOPIA (CBE / CBE Birr)
    // -------------------------------------------------------------
    if (senderUpper.contains('CBE') || lower.contains('cbe birr') || lower.contains('commercial bank of ethiopia') || lower.contains('የኢትዮጵያ ንግድ ባንክ')) {
      // Examples:
      // "Your account 1000*** was credited with ETB 500.00 by TESFAYE ALEMU. Txn ID: FT24123ABC... Current Balance is ETB 10,230.00"
      // "Dear customer ETB 350.00 credited to your account 1000123... on 12/10/2026. Ref No: FT26848201."
      final isCredit = lower.contains('credited') || lower.contains('ገቢ ተደርጓል') || lower.contains('deposited') || lower.contains('received');
      if (!isCredit && !lower.contains('ft')) return null;

      // Reference (usually starts with FT...)
      String? ref;
      final refMatch = RegExp(r'(?:txn\s*id|transaction\s*id|ref(?:erence)?\s*(?:no|number)?)\s*(?:is|:)?\s*([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text) ??
          RegExp(r'\b(FT[0-9A-Z]{8,18})\b', caseSensitive: false).firstMatch(text);
      if (refMatch != null) {
        ref = refMatch.group(1)?.trim().toUpperCase();
      }

      // Amount
      double? amt;
      final amtMatch = RegExp(r'(?:credited\s*(?:with)?|received|amount\s*of)\s*(?:ETB|Birr|ብር)?\s*' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(r'(?:ETB|Birr|ብር)\s*' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(_n + r'\s*(?:ETB|Birr|ብር)', caseSensitive: false).firstMatch(text);
      if (amtMatch != null) {
        amt = _parseAmount(amtMatch.group(1));
      }

      // Sender
      String? senderName;
      final nameMatch = RegExp(r'(?:by|from|ከ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at)', caseSensitive: false).firstMatch(text);
      if (nameMatch != null) {
        senderName = nameMatch.group(1)?.trim();
      }

      if (ref != null && amt != null && amt > 0) {
        return ParsedBankSms(
          reference: ref,
          amount: amt,
          provider: 'CBE',
          senderName: senderName,
          rawSms: text,
          receivedAt: time,
        );
      }
    }

    // -------------------------------------------------------------
    // OTHER ETHIOPIAN BANKS (Awash, Dashen, BOA, Sinqee, Wegagen)
    // -------------------------------------------------------------
    final isGeneralCredit = lower.contains('credited') || lower.contains('received') || lower.contains('deposited');
    if (isGeneralCredit) {
      String provider = 'Bank';
      if (senderUpper.contains('AWASH') || lower.contains('awash')) provider = 'Awash';
      if (senderUpper.contains('DASHEN') || lower.contains('dashen') || lower.contains('amole')) provider = 'Dashen';
      if (senderUpper.contains('ABYSSINIA') || senderUpper.contains('BOA') || lower.contains('abyssinia')) provider = 'Abyssinia';
      if (senderUpper.contains('SINQEE') || lower.contains('sinqee')) provider = 'Sinqee';
      if (senderUpper.contains('WEGAGEN') || lower.contains('wegagen')) provider = 'Wegagen';
      if (senderUpper.contains('HIBRET') || lower.contains('hibret')) provider = 'Hibret';

      // Look for Reference
      final refMatch = RegExp(r'(?:ref(?:erence)?(?:\s*no|\s*number)?|txn\s*id|transaction\s*id|code)\s*[:\-]?\s*([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text) ??
          RegExp(r'\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{8,18}\b').firstMatch(text);

      // Look for Amount
      final amtMatch = RegExp(r'(?:credited\s*(?:with)?|amount\s*of|ETB|Birr)\s*[:\-]?\s*' + _n, caseSensitive: false).firstMatch(text);

      if (refMatch != null && amtMatch != null) {
        final ref = refMatch.group(1)?.trim().toUpperCase();
        final amt = _parseAmount(amtMatch.group(1));
        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: provider,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    return null;
  }
}
