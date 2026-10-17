class ParsedReceipt {
  const ParsedReceipt({
    this.amount,
    this.netAmount,
    this.fee,
    this.totalPaid,
    this.reference,
    this.provider,
    this.sender,
    this.receiver,
    this.timeText,
    this.receiptUrl,
    this.rawText = '',
  });

  /// The net amount deposited to the merchant/business (excluding customer transfer fees)
  final double? amount;
  final double? netAmount;
  final double? fee;
  final double? totalPaid;
  final String? reference, provider, sender, receiver, timeText, receiptUrl;
  final String rawText;

  int get found => [amount, reference, provider].where((e) => e != null).length;
}

class OcrParser {
  static const _n = r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)';
  static const _cur = r'(?:ETB|Birr|Br\.?|ብር|Qarshii)?\s*';

  static final _providers = <String, RegExp>{
    'Telebirr': RegExp(r'tele\s?birr|ethio\s?telecom|ቴሌብር|ethiopian\s+telecom', caseSensitive: false),
    'CBE Birr': RegExp(r'cbe\s?birr|ሲቢኢ\s*ብር', caseSensitive: false),
    'CBE': RegExp(r'commercial\s+bank(?:\s+of\s+ethiopia)?|\bcbe\b|የኢትዮጵያ\s+ንግድ\s+ባንክ', caseSensitive: false),
    'Awash': RegExp(r'awash\s*(?:bank|birr)?|አዋሽ', caseSensitive: false),
    'Dashen': RegExp(r'dashen|amole|ዳሽን', caseSensitive: false),
    'Abyssinia': RegExp(r'abyssinia|boa\b|አቢሲኒያ', caseSensitive: false),
    'M-Pesa': RegExp(r'm-?pesa|safaricom|ኤምፔሳ', caseSensitive: false),
    'Zemen': RegExp(r'zemen|ዘመን', caseSensitive: false),
    'Wegagen': RegExp(r'wegagen|ወጋገን', caseSensitive: false),
    'Hibret': RegExp(r'hibret|lion\s+bank|ህብረት', caseSensitive: false),
    'Nib': RegExp(r'\bnib\b|ንብ', caseSensitive: false),
    'Oromia': RegExp(r'oromia|ኦሮሚያ', caseSensitive: false),
    'Coopay': RegExp(r'coopay|cooperative\s+bank|ኮኦፕ', caseSensitive: false),
    'Sinqee': RegExp(r'sinqee|ሲንቄ', caseSensitive: false),
    'Berhan': RegExp(r'berhan|ብርሃን', caseSensitive: false),
    'Abay': RegExp(r'abay\s+bank|አባይ', caseSensitive: false),
  };

  // 1. Explicit NET / TRANSFERRED amount patterns (Primary - money received by recipient)
  static final _netTransferredLabels = <RegExp>[
    // "Transferred Amount : 50.00 ETB", "Transfer Amount: 50.00", "Settled Amount: 50.00", "Credited Amount: 50.00"
    RegExp(
      r'(?:transferred\s*amount|transfer\s*amount|settled\s*amount|credited\s*amount|sent\s*amount|received\s*amount|net\s*amount|payment\s*amount|የተላለፈው\s*ገንዘብ|የተላለፈ\s*ሒሳብ|የተከፈለ\s*ገንዘብ|የተላከው)\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
  ];

  // 2. Explicit SERVICE FEE patterns (Platform / network charges)
  static final _serviceFeeLabels = <RegExp>[
    // "Service Fee : 1.00 ETB", "Service Fee (VAT incl.): 1.15", "Transaction Fee: 1.00", "Service Charge: 1.00"
    RegExp(
      r'(?:service\s*fee(?:\s*vat)?|transaction\s*fee|transfer\s*fee|service\s*charge|service\s*fee\s*amount|fee(?:\s*amount)?|charge|commission|የአገልግሎት\s*ክፍያ|የአገልግሎት\s*ክፍያ\s*ቫት|ኮሚሽን)\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
  ];

  // 3. Explicit GROSS / TOTAL PAID amount patterns (Payer's wallet deduction = Net + Fee)
  static final _totalPaidLabels = <RegExp>[
    // "Total Paid Amount : 51.00 ETB", "Total Paid : 51.00", "Total Payment: 51.00", "Total Debited: 51.00"
    RegExp(
      r'(?:total\s*(?:paid\s*)?amount|total\s*payment|total\s*paid|total\s*debited|debited\s*amount|total\s*transferred|total\s*deducted|total\s*charge|ጠቅላላ\s*ክፍያ|ጠቅላላ\s*የተከፈለ)\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
    // Fallback general total / payment / amount
    RegExp(r'(?:total|payment|amount|ሒሳብ|የተከፈለ)\s*[:\-]?\s*' + _cur + _n, caseSensitive: false),
  ];

  // Standalone currency pattern: ETB 100.00, 100.00 ETB, etc.
  static final _amountCurrencyBefore = RegExp(r'(?:ETB|Birr|Br\.?|ብር)\s*' + _n, caseSensitive: false);
  static final _amountCurrencyAfter = RegExp(_n + r'\s*(?:ETB|Birr|Br\.?|ብር)', caseSensitive: false);

  // Standalone numbers that look like an amount with decimal or minus sign
  // e.g. -101.00, +500.00, 100.00
  static final _standaloneAmountWithSign = RegExp(r'(?:^|\s)[-+]?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})(?:\s|$)', multiLine: true);
  static final _standaloneAmountDecimal = RegExp(r'(?:^|\s)([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})(?:\s|$)', multiLine: true);

  static final _refLabel = RegExp(
    r'(?:transaction\s*(?:number|no\.?|id|ref(?:erence)?|code)|reference\s*(?:number|no\.?|id|code)?|'
    r'ref\.?\s*(?:no\.?|number|id|code)?|receipt\s*(?:no\.?|number)|invoice\s*(?:no\.?|number)|'
    r'txn\s*(?:id|no\.?)|confirmation\s*(?:code|no\.?)|order\s*(?:no\.?|id)|የግብይት\s*ቁጥር)\s*[:\-#]?\s*([A-Za-z0-9]{6,30})',
    caseSensitive: false,
  );

  // Known Ethiopian Bank reference format patterns:
  static final _knownBankRefPatterns = <RegExp>[
    RegExp(r'\b(FT[0-9A-Z]{8,22})\b'), // CBE, BOA interbank
    RegExp(r'\b(DA[0-9A-Z]{6,18})\b'), // Dashen
    RegExp(r'\b(AW[0-9A-Z]{6,18})\b'), // Awash
    RegExp(r'\b(CP[0-9A-Z]{6,18})\b'), // Coop
    RegExp(r'\b(MP[0-9A-Z]{8,18})\b'), // M-Pesa
    RegExp(r'\b(SQ[0-9A-Z]{6,18})\b'), // Sinqee
    RegExp(r'\b(WG[0-9A-Z]{6,18})\b'), // Wegagen
    RegExp(r'\b(HB[0-9A-Z]{6,18})\b'), // Hibret
  ];

  static final _senderLabels = <RegExp>[
    RegExp(
      r"(?:sender(?:\s*name)?|from|payer|paid\s*by|debited\s*from|customer(?:\s*name)?|ከ|የከፋይ)\s*[:\-]?\s*([A-Za-z][A-Za-z0-9 .'-]{2,40})",
      caseSensitive: false,
    ),
    RegExp(r"(?:account\s*holder|acc\s*name)\s*[:\-]?\s*([A-Za-z][A-Za-z0-9 .'-]{2,40})", caseSensitive: false),
  ];

  static final _receiverLabels = <RegExp>[
    RegExp(
      r"(?:receiver(?:\s*name)?|recipient|merchant|creditor|paid\s*to|ለ|የተቀባይ)\s*[:\-]?\s*([A-Za-z][A-Za-z0-9 .'-]{2,40})",
      caseSensitive: false,
    ),
    RegExp(
      r"\bto\s*[:\-]\s*([A-Za-z][A-Za-z0-9 .'-]{2,40})",
      caseSensitive: false,
    ),
  ];

  static final _timeRegex = RegExp(
    r'\b(?:\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|\d{4}[-/.]\d{1,2}[-/.]\d{1,2})[ T,]*(?:\d{1,2}:\d{2}(?::\d{2})?\s?(?:[AaPp][Mm])?)?',
  );

  static double? _num(String? s) {
    if (s == null) return null;
    final cleaned = s.replaceAll(',', '').replaceAll(' ', '').trim();
    final v = double.tryParse(cleaned);
    return (v != null && v > 0) ? v : null;
  }

  static ParsedReceipt parse(String raw, {String? qrUrl}) {
    final text = raw.replaceAll('\r', '');
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // 1. Detect Provider
    String? provider;
    for (final e in _providers.entries) {
      if (e.value.hasMatch(text)) {
        provider = e.key;
        break;
      }
    }
    // Infer provider from QR URL if not in text
    if (provider == null && qrUrl != null) {
      final urlLower = qrUrl.toLowerCase();
      if (urlLower.contains('cbe.com.et') || urlLower.contains('cbe')) {
        provider = 'CBE';
      } else if (urlLower.contains('telebirr') || urlLower.contains('ethiotelecom')) {
        provider = 'Telebirr';
      } else if (urlLower.contains('awash')) {
        provider = 'Awash';
      } else if (urlLower.contains('dashen')) {
        provider = 'Dashen';
      } else if (urlLower.contains('bankofabyssinia') || urlLower.contains('abyssinia')) {
        provider = 'Abyssinia';
      }
    }

    // 2. Detect Reference Number
    String? reference;
    for (final m in _refLabel.allMatches(text)) {
      final tok = m.group(1)!;
      // Must have at least 1 digit and 1 letter or length >= 6
      if (RegExp(r'\d').hasMatch(tok) && RegExp(r'[A-Za-z]').hasMatch(tok) && tok.length >= 6 && tok.length <= 30) {
        final upper = tok.toUpperCase();
        if (!upper.startsWith('202') && !upper.startsWith('DATE') && !upper.contains('HOTEL') && !upper.contains('REST')) {
          reference = upper;
          break;
        }
      }
    }
    // Check known digital receipt URLs in OCR text or scanned QR code
    if (reference == null) {
      final urlSource = '$text\n${qrUrl ?? ''}';
      final urlCbe = RegExp(r'mbreciept\.cbe\.com\.et\/([A-Za-z0-9_\-]+)', caseSensitive: false).firstMatch(urlSource);
      if (urlCbe != null) {
        reference = urlCbe.group(1)?.trim();
        provider ??= 'CBE';
      }
    }
    if (reference == null) {
      final urlSource = '$text\n${qrUrl ?? ''}';
      final urlTrx = RegExp(r'(?:slip/\?trx=|trx=|[?&]id=|[?&]ref=)([A-Za-z0-9_\-]{6,30})', caseSensitive: false).firstMatch(urlSource);
      if (urlTrx != null) {
        reference = urlTrx.group(1)?.trim().toUpperCase();
      }
    }
    if (reference == null) {
      final urlTrx = RegExp(r'(?:slip/\?trx=|trx=)([A-Za-z0-9]{8,24})', caseSensitive: false).firstMatch(text);
      if (urlTrx != null) {
        reference = urlTrx.group(1)?.trim().toUpperCase();
      }
    }
    // High-confidence bank reference patterns (FT, DA, AW, CP, MP, SQ, WG, HB)
    if (reference == null) {
      for (final re in _knownBankRefPatterns) {
        final m = re.firstMatch(text.toUpperCase());
        if (m != null) {
          reference = m.group(1);
          break;
        }
      }
    }
    // Telebirr 10-char alphanumeric ONLY if document is confirmed Telebirr
    if (reference == null && (provider == 'Telebirr' || text.toLowerCase().contains('telebirr'))) {
      final m = RegExp(r'\b([A-Z0-9]{10})\b').firstMatch(text.toUpperCase());
      if (m != null && RegExp(r'\d').hasMatch(m.group(1)!) && RegExp(r'[A-Z]').hasMatch(m.group(1)!)) {
        reference = m.group(1);
      }
    }
    // Note: If no explicit label or known bank pattern matches, reference remains null.
    // We do NOT guess or pick random OCR words as transaction IDs.

    // 3. Detect Amount (Distinguishing Net Transferred vs. Customer Platform Fee vs. Total Paid)
    double? netAmount;
    for (final re in _netTransferredLabels) {
      final m = re.firstMatch(text);
      if (m != null) {
        netAmount = _num(m.group(1));
        if (netAmount != null) break;
      }
    }

    double? fee;
    for (final re in _serviceFeeLabels) {
      final m = re.firstMatch(text);
      if (m != null) {
        fee = _num(m.group(1));
        if (fee != null && fee < 1000) break;
      }
    }

    double? totalPaid;
    for (final re in _totalPaidLabels) {
      final m = re.firstMatch(text);
      if (m != null) {
        totalPaid = _num(m.group(1));
        if (totalPaid != null) break;
      }
    }

    // Multi-line label scanning (e.g. line 1: "Transferred Amount", line 2: "50.00 ETB")
    if (netAmount == null) {
      for (var i = 0; i < lines.length - 1; i++) {
        final cur = lines[i].toLowerCase();
        if (cur.contains('transferred amount') ||
            cur.contains('transfer amount') ||
            cur.contains('settled amount') ||
            cur.contains('received amount') ||
            cur.contains('የተላለፈው ገንዘብ')) {
          final next = lines[i + 1];
          final nm = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)').firstMatch(next);
          if (nm != null) {
            netAmount = _num(nm.group(1));
            if (netAmount != null) break;
          }
        }
      }
    }

    if (fee == null) {
      for (var i = 0; i < lines.length - 1; i++) {
        final cur = lines[i].toLowerCase();
        if (cur.contains('service fee') ||
            cur.contains('service charge') ||
            cur.contains('transfer fee') ||
            cur == 'fee' ||
            cur.contains('የአገልግሎት ክፍያ')) {
          final next = lines[i + 1];
          final nm = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)').firstMatch(next);
          if (nm != null) {
            fee = _num(nm.group(1));
            if (fee != null && fee < 1000) break;
          }
        }
      }
    }

    if (totalPaid == null) {
      for (var i = 0; i < lines.length - 1; i++) {
        final cur = lines[i].toLowerCase();
        if (cur.contains('total paid') || cur.contains('total amount') || cur == 'total' || cur.contains('ጠቅላላ ክፍያ')) {
          final next = lines[i + 1];
          final nm = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)').firstMatch(next);
          if (nm != null) {
            totalPaid = _num(nm.group(1));
            if (totalPaid != null) break;
          }
        }
      }
    }

    // Determine primary merchant amount
    double? amount;
    if (netAmount != null) {
      // Direct net transferred amount received by merchant
      amount = netAmount;
      if (totalPaid == null && fee != null) {
        totalPaid = double.parse((netAmount + fee).toStringAsFixed(2));
      }
    } else if (totalPaid != null && fee != null && totalPaid > fee) {
      // Deduce net: Total Paid - Service Fee = Net received!
      amount = double.parse((totalPaid - fee).toStringAsFixed(2));
      netAmount = amount;
    } else if (totalPaid != null) {
      amount = totalPaid;
    }

    // Pass B: Standalone currency with ETB / Birr before or after
    if (amount == null) {
      final candidates = <double>[];
      for (final m in _amountCurrencyBefore.allMatches(text)) {
        final v = _num(m.group(1));
        if (v != null) candidates.add(v);
      }
      for (final m in _amountCurrencyAfter.allMatches(text)) {
        final v = _num(m.group(1));
        if (v != null) candidates.add(v);
      }
      if (candidates.isNotEmpty) {
        final plausible = candidates.where((c) => c < 10000000).toList();
        if (plausible.isNotEmpty) {
          // If 3 numbers match Total, Net, and Fee (e.g. 51, 50, 1)
          if (plausible.length >= 3) {
            final sorted = [...plausible]..sort((a, b) => b.compareTo(a));
            for (var i = 0; i < sorted.length - 1; i++) {
              for (var j = i + 1; j < sorted.length; j++) {
                final diff = double.parse((sorted[i] - sorted[j]).toStringAsFixed(2));
                if (diff > 0 && diff <= 25.0 && sorted.contains(diff)) {
                  totalPaid ??= sorted[i];
                  netAmount ??= sorted[j];
                  fee ??= diff;
                  amount = sorted[j];
                  break;
                }
              }
              if (amount != null) break;
            }
          }
          amount ??= plausible.first;
        }
      }
    }

    // Pass C: Line scanning for standalone signed numbers (e.g. "-100.00" or "+100.00")
    if (amount == null) {
      for (final line in lines) {
        final sm = _standaloneAmountWithSign.firstMatch(line);
        if (sm != null) {
          final v = _num(sm.group(1));
          if (v != null && v < 10000000) {
            amount = v;
            break;
          }
        }
      }
    }

    // Pass D: Scan line containing decimals (e.g. "100.00" alone on a line or header)
    if (amount == null) {
      for (final line in lines) {
        final cleanLine = line.replaceAll(RegExp(r'[^0-9.,]'), '');
        final dm = _standaloneAmountDecimal.firstMatch(cleanLine);
        if (dm != null) {
          final v = _num(dm.group(1));
          if (v != null && v > 0.5 && v < 5000000 && !line.contains(RegExp(r'202\d|199\d'))) {
            amount = v;
            break;
          }
        }
      }
    }

    // Pass E: Check line immediately following "Amount", "Total", or "Payment"
    if (amount == null) {
      for (var i = 0; i < lines.length - 1; i++) {
        final cur = lines[i].toLowerCase();
        if (cur.contains('amount') || cur.contains('total') || cur.contains('paid') || cur.contains('birr')) {
          final next = lines[i + 1];
          final nm = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)').firstMatch(next);
          if (nm != null) {
            final v = _num(nm.group(1));
            if (v != null && v < 10000000) {
              amount = v;
              break;
            }
          }
        }
      }
    }

    // 4. Detect Sender Name
    String? sender;
    for (final re in _senderLabels) {
      final m = re.firstMatch(text);
      if (m != null) {
        final cand = m.group(1)?.trim();
        if (cand != null && !_isBlacklistedWord(cand)) {
          sender = _cleanPersonName(cand);
          if (sender.isNotEmpty) break;
        }
      }
    }

    // Multi-line sender: line contains "Sender" or "Payer" or "From", name is on next line
    if (sender == null || sender.isEmpty) {
      for (var i = 0; i < lines.length - 1; i++) {
        final l = lines[i].toLowerCase();
        if (l == 'sender' || l == 'payer' || l == 'from' || l == 'sender name' || l == 'paid by' || l == 'debited from') {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !_isBlacklistedWord(next) && RegExp(r'^[A-Za-z]').hasMatch(next)) {
            sender = _cleanPersonName(next);
            if (sender.isNotEmpty) break;
          }
        }
      }
    }

    // 5. Detect Receiver Name
    String? receiver;
    for (final re in _receiverLabels) {
      final m = re.firstMatch(text);
      if (m != null) {
        final cand = m.group(1)?.trim();
        if (cand != null && !_isBlacklistedWord(cand)) {
          receiver = _cleanPersonName(cand);
          if (receiver.isNotEmpty) break;
        }
      }
    }

    // 6. Detect Timestamp
    final timeMatch = _timeRegex.firstMatch(text);
    final time = timeMatch?.group(0)?.trim();

    return ParsedReceipt(
      amount: amount,
      netAmount: netAmount ?? amount,
      fee: fee,
      totalPaid: totalPaid,
      reference: reference,
      provider: provider,
      sender: sender?.isEmpty == true ? null : sender,
      receiver: receiver?.isEmpty == true ? null : receiver,
      timeText: time,
      receiptUrl: qrUrl,
      rawText: text,
    );
  }

  static bool _isBlacklistedWord(String s) {
    final lower = s.toLowerCase();
    const bad = [
      'amount', 'total', 'date', 'time', 'reference', 'number', 'account', 'successful',
      'completed', 'transaction', 'telebirr', 'cbe', 'birr', 'bank', 'etb', 'transfer',
    ];
    return bad.any((b) => lower == b);
  }

  static String _cleanPersonName(String s) {
    // Remove trailing colons, semicolons, dashes, or extraneous non-alphabet characters
    return s.replaceAll(RegExp(r'[:\-–—\(\)\[\]]'), '').trim();
  }
}

