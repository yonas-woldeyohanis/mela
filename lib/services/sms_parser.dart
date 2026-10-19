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
  // Ethiopian Currency indicators: ETB, Birr, Br, ብር, Qarshii
  static const _curr = r'(?:ETB|Birr|Br|ብር|Qarshii)';

  // Number regex: 100, 100.00, 1,250.50
  static const _n = r'([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)';

  static double? _parseAmount(String? str) {
    if (str == null) return null;
    final cleaned = str.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  static double? _extractBalance(String text) {
    final m = RegExp(
      r'(?:current\s*balance|available\s*balance|balance|ቀሪ\s*ሒሳብ|ሒሳብ)\s*(?:is|:)?\s*(?:' +
          _curr +
          r'\.?\s*)?' +
          _n +
          r'(?:\s*' +
          _curr +
          r'\.?)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) {
      return _parseAmount(m.group(1));
    }
    return null;
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
    // 1. CBE BIRR (Evaluated before general CBE to prevent overlap)
    // -------------------------------------------------------------
    if (senderUpper.contains('CBE BIRR') ||
        senderUpper.contains('CBEBIRR') ||
        lower.contains('cbe birr account') ||
        lower.contains('cbebirr account')) {
      final isCredit = lower.contains('credited') || lower.contains('received') || lower.contains('ገቢ');
      if (isCredit) {
        String? ref;
        final refMatch = RegExp(r'(?:txn\s*id|transaction\s*id|ref(?:erence)?\s*(?:no|number)?)\s*[:\-]?\s*([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b([A-Z0-9]{10,14})\b').firstMatch(text);
        if (refMatch != null) ref = refMatch.group(1)?.trim().toUpperCase();

        double? amt;
        final amtMatch = RegExp(
          r'(?:credited\s*(?:with)?|received)\s*(?:' + _curr + r'\.?\s*)?' + _n + r'(?:\s*' + _curr + r'\.?)?',
          caseSensitive: false,
        ).firstMatch(text) ??
            RegExp(_n + r'\s*' + _curr + r'\.?', caseSensitive: false).firstMatch(text);
        if (amtMatch != null) amt = _parseAmount(amtMatch.group(1));

        final bal = _extractBalance(text);

        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: 'CBE Birr',
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 2. BANK OF ABYSSINIA (BOA) / APOLLO
    // (Evaluated before CBE so inter-bank transfers mentioning CBE don't misclassify)
    // -------------------------------------------------------------
    if (senderUpper.contains('ABYSSINIA') ||
        senderUpper.contains('BOA') ||
        senderUpper.contains('APOLLO') ||
        lower.contains('bankofabyssinia.com') ||
        lower.contains('bank of abyssinia') ||
        lower.contains('አቢሲኒያ ባንክ')) {
      final isCredit = lower.contains('credited') || lower.contains('deposited') || lower.contains('received') || lower.contains('ገቢ');
      if (isCredit) {
        String? ref;
        final urlMatch = RegExp(r'(?:slip/\?trx=|trx=)([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text);
        if (urlMatch != null) {
          ref = urlMatch.group(1)?.trim().toUpperCase();
        }
        if (ref == null) {
          final ftMatch = RegExp(r'\b(FT[0-9A-Z]{8,22})\b', caseSensitive: false).firstMatch(text);
          if (ftMatch != null) ref = ftMatch.group(1)?.trim().toUpperCase();
        }
        if (ref == null) {
          final refMatch = RegExp(r'(?:ref(?:erence)?(?:\s*no|\s*number)?|txn\s*id|transaction\s*id|code|መለያ|ማጣቀሻ)\s*[:\-]?\s*([A-Za-z0-9]{6,24})', caseSensitive: false).firstMatch(text) ??
              RegExp(r'\b(BOA[0-9A-Z]{6,18})\b', caseSensitive: false).firstMatch(text);
          if (refMatch != null) ref = refMatch.group(1)?.trim().toUpperCase();
        }

        double? amt;
        final amtMatch = RegExp(
          r'(?:credited\s*(?:with)?|deposited|amount\s*(?:of)?|received)\s*(?:' + _curr + r'\.?\s*)?' + _n,
          caseSensitive: false,
        ).firstMatch(text) ??
            RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
            RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);
        if (amtMatch != null) amt = _parseAmount(amtMatch.group(1));

        String? senderName;
        final nameMatch = RegExp(r'by\s+([A-Za-z\s]+?)(?:\s+from|\s+on|\s*\.|\s+ref|\s+txn)', caseSensitive: false).firstMatch(text) ??
            RegExp(r'(?:from|ከ|በ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at|\s*\(|\s*ገቢ)', caseSensitive: false).firstMatch(text);
        if (nameMatch != null) senderName = nameMatch.group(1)?.trim();

        final bal = _extractBalance(text);

        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: 'Abyssinia',
            senderName: senderName,
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 3. TELEBIRR (Sender usually "127", "telebirr", "EthioTelecom")
    // -------------------------------------------------------------
    if (senderUpper == '127' || senderUpper.contains('TELEBIRR') || lower.contains('telebirr') || lower.contains('ቴሌብር')) {
      final isIncoming = lower.contains('received') ||
          lower.contains('ደርሶዎታል') ||
          lower.contains('ገቢ ተደርጓል') ||
          lower.contains('ገቢ ሆኗል') ||
          lower.contains('ሒሳብዎ ገቢ') ||
          lower.contains('credited') ||
          lower.contains('transfer to end user');

      if (!isIncoming) {
        return null;
      }

      String? ref;
      final refMatch = RegExp(
        r'(?:(?:by\s+)?transaction\s*(?:number|no|id)|የግብይት\s*ቁጥር)\s*(?:is|:)?\s*([A-Za-z0-9]{8,18})',
        caseSensitive: false,
      ).firstMatch(text) ??
          RegExp(r'\b([A-Z0-9]{10})\b').firstMatch(text);
      if (refMatch != null) {
        ref = refMatch.group(1)?.trim().toUpperCase();
      }

      double? amt;
      final amtMatch = RegExp(
        r'(?:received|ደርሶዎታል|ገቢ)\s*(?:' + _curr + r'\.?\s*)?' + _n,
        caseSensitive: false,
      ).firstMatch(text) ??
          RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(_n + r'\s*' + _curr, caseSensitive: false).firstMatch(text);
      if (amtMatch != null) {
        amt = _parseAmount(amtMatch.group(1));
      }

      String? senderName;
      final nameMatch = RegExp(
        r'(?:from|ከ)\s+([A-Za-z0-9\s]+?)(?:\s+to\s+your|\s*\(|\s+on|\s+at|\s*\.|\s+ደርሶዎታል|\s+trans)',
        caseSensitive: false,
      ).firstMatch(text);
      if (nameMatch != null) {
        senderName = nameMatch.group(1)?.trim();
      }

      String? receiverPhone;
      final phoneMatch = RegExp(r'to\s+your\s+telebirr\s+Account\s+([0-9]{9,12})', caseSensitive: false).firstMatch(text);
      if (phoneMatch != null) {
        receiverPhone = phoneMatch.group(1);
      }

      final bal = _extractBalance(text);

      if (ref != null && amt != null && amt > 0) {
        return ParsedBankSms(
          reference: ref,
          amount: amt,
          provider: 'Telebirr',
          senderName: senderName,
          receiverPhone: receiverPhone,
          balance: bal,
          rawSms: text,
          receivedAt: time,
        );
      }
    }

    // -------------------------------------------------------------
    // 4. COMMERCIAL BANK OF ETHIOPIA (CBE)
    // -------------------------------------------------------------
    if (senderUpper.contains('CBE') ||
        lower.contains('commercial bank of ethiopia') ||
        lower.contains('banking with cbe') ||
        lower.contains('የኢትዮጵያ ንግድ ባንክ') ||
        lower.contains('cbe.com.et')) {
      final isCredit = lower.contains('credited') ||
          lower.contains('ገቢ ተደርጓል') ||
          lower.contains('ገቢ ሆኗል') ||
          lower.contains('ሒሳብዎ ገቢ') ||
          lower.contains('deposited') ||
          lower.contains('received');
      if (!isCredit) return null;

      String? ref;
      final urlMatch = RegExp(r'mbreciept\.cbe\.com\.et\/([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(text);
      if (urlMatch != null) {
        ref = urlMatch.group(1)?.trim();
      }
      if (ref == null) {
        final ftMatch = RegExp(r'\b(FT[0-9A-Z]{8,22})\b', caseSensitive: false).firstMatch(text);
        if (ftMatch != null) ref = ftMatch.group(1)?.trim().toUpperCase();
      }
      if (ref == null) {
        final txnMatch = RegExp(r'(?:txn\s*id|transaction\s*id|ref(?:erence)?\s*(?:no|number)?)\s*(?:is|:)?\s*([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text);
        if (txnMatch != null) ref = txnMatch.group(1)?.trim().toUpperCase();
      }

      double? amt;
      final amtMatch = RegExp(
        r'(?:credited\s*(?:with)?|received|amount\s*of)\s*(?:' + _curr + r'\.?\s*)?' + _n,
        caseSensitive: false,
      ).firstMatch(text) ??
          RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);
      if (amtMatch != null) {
        amt = _parseAmount(amtMatch.group(1));
      }

      String? senderName;
      final acctSenderMatch = RegExp(r'from\s+account\s+\S+\s*\(([^)]+)\)', caseSensitive: false).firstMatch(text);
      if (acctSenderMatch != null) {
        senderName = acctSenderMatch.group(1)?.trim();
      } else {
        final nameMatch = RegExp(r'(?:by|from|ከ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at|\s+to)', caseSensitive: false).firstMatch(text);
        if (nameMatch != null) senderName = nameMatch.group(1)?.trim();
      }

      final bal = _extractBalance(text);

      if (ref != null && amt != null && amt > 0) {
        return ParsedBankSms(
          reference: ref,
          amount: amt,
          provider: 'CBE',
          senderName: senderName,
          balance: bal,
          rawSms: text,
          receivedAt: time,
        );
      }
    }

    // -------------------------------------------------------------
    // 5. DASHEN BANK / AMOLE (8899)
    // -------------------------------------------------------------
    if (senderUpper.contains('DASHEN') || senderUpper.contains('AMOLE') || senderUpper == '8899' || lower.contains('dashen') || lower.contains('amole') || lower.contains('ዳሽን ባንክ')) {
      final isCredit = lower.contains('credited') || lower.contains('received') || lower.contains('deposited') || lower.contains('ገቢ') || lower.contains('ደርሶዎታል');
      if (isCredit) {
        String? ref;
        final refMatch = RegExp(r'(?:txn\s*ref|ref(?:erence)?(?:\s*no|\s*number)?|txn\s*id|transaction\s*id|ማጣቀሻ|መለያ)\s*[:\-]?\s*([A-Za-z0-9]{6,24})', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b(DA[0-9A-Z]{6,18})\b', caseSensitive: false).firstMatch(text) ??
            RegExp(r'(?:trx=|ref=)([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text);
        if (refMatch != null) ref = refMatch.group(1)?.trim().toUpperCase();

        // Fallback synthetic ref for interbank Dashen notification without explicit txn id:
        // "on 22/07/2026 at 06:29:51 AM" -> "DA20260722-062951AM"
        if (ref == null) {
          final dtMatch = RegExp(r'on\s+(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})\s+at\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?\s*([AP]M)?', caseSensitive: false).firstMatch(text);
          if (dtMatch != null) {
            final d = dtMatch.group(1)!.padLeft(2, '0');
            final m = dtMatch.group(2)!.padLeft(2, '0');
            final y = dtMatch.group(3)!;
            final hr = dtMatch.group(4)!.padLeft(2, '0');
            final mn = dtMatch.group(5)!.padLeft(2, '0');
            final sec = (dtMatch.group(6) ?? '00').padLeft(2, '0');
            final ampm = (dtMatch.group(7) ?? '').toUpperCase();
            ref = 'DA$y$m$d-$hr$mn$sec$ampm';
          }
        }

        double? amt;
        final amtMatch = RegExp(
          r'(?:credited\s*(?:with)?|amount\s*(?:of)?|received)\s*(?:' + _curr + r'\.?\s*)?' + _n,
          caseSensitive: false,
        ).firstMatch(text) ??
            RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
            RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);
        if (amtMatch != null) amt = _parseAmount(amtMatch.group(1));

        String? senderName;
        final nameMatch = RegExp(r'(?:from|by|ከ|በ)\s+([^.\n]+?)(?:\s+on|\s+at|\s*\.|\s+ref|\s+txn)', caseSensitive: false).firstMatch(text);
        if (nameMatch != null) senderName = nameMatch.group(1)?.trim();

        final bal = _extractBalance(text);

        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: 'Dashen',
            senderName: senderName,
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 6. AWASH BANK (881)
    // -------------------------------------------------------------
    if (senderUpper.contains('AWASH') || senderUpper == '881' || lower.contains('awash') || lower.contains('አዋሽ ባንክ')) {
      final isCredit = lower.contains('credited') || lower.contains('received') || lower.contains('ገቢ') || lower.contains('ደርሶዎታል');
      if (isCredit) {
        String? ref;
        final refMatch = RegExp(r'(?:trans\s*ref|ref(?:erence)?(?:\s*no|\s*number)?|txn\s*id|transaction\s*id|ማጣቀሻ|መለያ)\s*[:\-]?\s*([A-Za-z0-9]{6,24})', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b(AW[0-9A-Z]{6,18})\b', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b([A-Z0-9]{8,18})\b').firstMatch(text);
        if (refMatch != null) ref = refMatch.group(1)?.trim().toUpperCase();

        double? amt;
        final amtMatch = RegExp(
          r'(?:credited\s*(?:with)?|amount\s*(?:of)?|received)\s*(?:' + _curr + r'\.?\s*)?' + _n,
          caseSensitive: false,
        ).firstMatch(text) ??
            RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
            RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);
        if (amtMatch != null) amt = _parseAmount(amtMatch.group(1));

        String? senderName;
        final nameMatch = RegExp(r'(?:from|by|ከ|በ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at|\s*\(|\s*ገቢ)', caseSensitive: false).firstMatch(text);
        if (nameMatch != null) senderName = nameMatch.group(1)?.trim();

        final bal = _extractBalance(text);

        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: 'Awash',
            senderName: senderName,
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 7. COOPERATIVE BANK OF OROMIA (COOP / COOPAY / COOPAY-EBIRR)
    // -------------------------------------------------------------
    if (senderUpper.contains('COOP') || lower.contains('coopbank') || lower.contains('coopay') || lower.contains('ህብረት ስራ ባንክ')) {
      final isCredit = lower.contains('credited') || lower.contains('received') || lower.contains('galii') || lower.contains('ገቢ');
      if (isCredit) {
        String? ref;
        final refMatch = RegExp(r'(?:txn\s*ref|ref(?:erence)?(?:\s*no|\s*number)?|txn\s*id|transaction\s*id|መለያ)\s*[:\-]?\s*([A-Za-z0-9]{6,24})', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b(CP[0-9A-Z]{6,18})\b', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b([A-Z0-9]{8,18})\b').firstMatch(text);
        if (refMatch != null) ref = refMatch.group(1)?.trim().toUpperCase();

        double? amt;
        final amtMatch = RegExp(
          r'(?:credited\s*(?:with)?|amount\s*(?:of)?|received)\s*(?:' + _curr + r'\.?\s*)?' + _n,
          caseSensitive: false,
        ).firstMatch(text) ??
            RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
            RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);
        if (amtMatch != null) amt = _parseAmount(amtMatch.group(1));

        String? senderName;
        final nameMatch = RegExp(r'(?:from|by|ከ|በ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at|\s*\(|\s*ገቢ)', caseSensitive: false).firstMatch(text);
        if (nameMatch != null) senderName = nameMatch.group(1)?.trim();

        final bal = _extractBalance(text);

        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: 'Coop',
            senderName: senderName,
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 8. M-PESA (SAFARICOM ETHIOPIA)
    // -------------------------------------------------------------
    if (senderUpper.contains('MPESA') || senderUpper.contains('M-PESA') || senderUpper.contains('SAFARICOM') || lower.contains('m-pesa')) {
      final isCredit = lower.contains('received') || lower.contains('credited') || lower.contains('ገቢ') || lower.contains('ደርሶዎታል');
      if (isCredit) {
        String? ref;
        final refMatch = RegExp(r'(?:transaction\s*id|txn\s*id|ref(?:erence)?|code)\s*[:\-]?\s*([A-Za-z0-9]{8,18})', caseSensitive: false).firstMatch(text) ??
            RegExp(r'\b([A-Z0-9]{10})\b').firstMatch(text);
        if (refMatch != null) ref = refMatch.group(1)?.trim().toUpperCase();

        double? amt;
        final amtMatch = RegExp(
          r'(?:received|amount\s*(?:of)?)\s*(?:' + _curr + r'\.?\s*)?' + _n,
          caseSensitive: false,
        ).firstMatch(text) ??
            RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
            RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);
        if (amtMatch != null) amt = _parseAmount(amtMatch.group(1));

        String? senderName;
        final nameMatch = RegExp(r'(?:from|ከ)\s+([A-Za-z\s]+?)(?:\s+on|\s*\.|\s*\(|\s+251)', caseSensitive: false).firstMatch(text);
        if (nameMatch != null) senderName = nameMatch.group(1)?.trim();

        final bal = _extractBalance(text);

        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: 'M-Pesa',
            senderName: senderName,
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    // -------------------------------------------------------------
    // 9. UNIVERSAL PARSER FOR ALL ETHIOPIAN BANKS & INSTITUTIONS
    // (Siinqee, Zemen, Nib, Hibret, Wegagen, Berhan, Enat, Amhara,
    //  Global, Tsedey, Gadaa, Hijra, ZamZam, Rammis, Sidama, etc.)
    // -------------------------------------------------------------
    final isGeneralCredit = lower.contains('credited') ||
        lower.contains('received') ||
        lower.contains('deposited') ||
        lower.contains('ገቢ ተደርጓል') ||
        lower.contains('ገቢ ሆኗል') ||
        lower.contains('ደርሶዎታል') ||
        lower.contains('galii ta\'eera');

    if (isGeneralCredit) {
      String provider = 'Bank';
      if (senderUpper.contains('SINQEE') || senderUpper.contains('SIINQEE') || lower.contains('sinqee') || lower.contains('siinqee')) {
        provider = 'Sinqee';
      } else if (senderUpper.contains('ZEMEN') || lower.contains('zemen')) {
        provider = 'Zemen';
      } else if (senderUpper.contains('NIB') || lower.contains('nib')) {
        provider = 'Nib';
      } else if (senderUpper.contains('HIBRET') || senderUpper.contains('UNITED') || lower.contains('hibret')) {
        provider = 'Hibret';
      } else if (senderUpper.contains('WEGAGEN') || lower.contains('wegagen')) {
        provider = 'Wegagen';
      } else if (senderUpper.contains('BERHAN') || lower.contains('berhan')) {
        provider = 'Berhan';
      } else if (senderUpper.contains('OROMIA') || lower.contains('oromia')) {
        provider = 'Oromia';
      } else if (senderUpper.contains('AMHARA') || lower.contains('amhara')) {
        provider = 'Amhara';
      } else if (senderUpper.contains('ENAT') || lower.contains('enat')) {
        provider = 'Enat';
      } else if (senderUpper.contains('GLOBAL') || lower.contains('global')) {
        provider = 'Global';
      } else if (senderUpper.contains('TSEDEY') || lower.contains('tsedey')) {
        provider = 'Tsedey';
      } else if (senderUpper.contains('GADAA') || lower.contains('gadaa')) {
        provider = 'Gadaa';
      } else if (senderUpper.contains('HIJRA') || lower.contains('hijra')) {
        provider = 'Hijra';
      } else if (senderUpper.contains('ZAMZAM') || lower.contains('zamzam')) {
        provider = 'ZamZam';
      } else if (senderUpper.contains('RAMMIS') || lower.contains('rammis')) {
        provider = 'Rammis';
      } else if (senderUpper.contains('SIDAMA') || lower.contains('sidama')) {
        provider = 'Sidama';
      }

      // Look for Reference
      final refMatch = RegExp(r'(?:ref(?:erence)?(?:\s*no|\s*number)?|txn\s*(?:id|no|num)|transaction\s*(?:id|number|no)|code|መለያ|ማጣቀሻ|ቁጥር)\s*[:\-]?\s*([A-Za-z0-9]{6,26})', caseSensitive: false).firstMatch(text) ??
          RegExp(r'\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{8,18}\b').firstMatch(text);

      // Look for Amount
      final amtMatch = RegExp(
        r'(?:credited\s*(?:with)?|amount\s*(?:of)?|received|ገቢ)\s*(?:' + _curr + r'\.?\s*)?' + _n,
        caseSensitive: false,
      ).firstMatch(text) ??
          RegExp(r'(?:' + _curr + r'\.?\s*)' + _n, caseSensitive: false).firstMatch(text) ??
          RegExp(_n + r'\s*(?:' + _curr + r'\.?)', caseSensitive: false).firstMatch(text);

      // Look for Sender
      String? senderName;
      final nameMatch = RegExp(r'(?:from|by|ከ|በ)\s+([A-Za-z\s]+?)(?:\s*\.|\s+ref|\s+txn|\s+on|\s+at|\s*\(|\s*ገቢ)', caseSensitive: false).firstMatch(text);
      if (nameMatch != null) senderName = nameMatch.group(1)?.trim();

      final bal = _extractBalance(text);

      if (refMatch != null && amtMatch != null) {
        final ref = refMatch.group(1)?.trim().toUpperCase();
        final amt = _parseAmount(amtMatch.group(1));
        if (ref != null && amt != null && amt > 0) {
          return ParsedBankSms(
            reference: ref,
            amount: amt,
            provider: provider,
            senderName: senderName,
            balance: bal,
            rawSms: text,
            receivedAt: time,
          );
        }
      }
    }

    return null;
  }
}
