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
    'Telebirr': RegExp(
      r'tele\s?birr|ethio\s?telecom|ቴሌብር|ethiopian\s+telecom|'
      r'transaction\s*type\s*:\s*(?:transfer\s*money|send\s*money|pay\s*merchant)|'
      r'transaction\s*number\s*:\s*DJ[A-Z0-9]{8}',
      caseSensitive: false,
    ),
    'CBE Birr': RegExp(r'cbe\s?birr|ሲቢኢ\s*ብር', caseSensitive: false),
    'CBE': RegExp(r'commercial\s+bank(?:\s+of\s+ethiopia)?|\bcbe\b|የኢትዮጵያ\s+ንግድ\s+ባንክ', caseSensitive: false),
    'Awash': RegExp(r'awash\s*(?:bank|birr)?|አዋሽ', caseSensitive: false),
    'Dashen': RegExp(r'dashen|amole|ዳሽን', caseSensitive: false),
    'Abyssinia': RegExp(r'abyssinia|boa\b|አቢሲኒያ', caseSensitive: false),
    'M-Pesa': RegExp(r'm-?pesa|safaricom|ኤምፔሳ', caseSensitive: false),
    'Zemen': RegExp(r'\bzemen\s*(?:bank|ባንክ)?\b(?!\s*gebeya)|\bዘመን\s*ባንክ\b', caseSensitive: false),
    'Wegagen': RegExp(r'wegagen|ወጋገን', caseSensitive: false),
    'Hibret': RegExp(r'hibret|lion\s+bank|ህብረት', caseSensitive: false),
    'Nib': RegExp(r'\bnib\b|ንብ', caseSensitive: false),
    'Oromia': RegExp(r'oromia|ኦሮሚያ', caseSensitive: false),
    'Coopay': RegExp(r'coopay|cooperative\s+bank|ኮኦፕ', caseSensitive: false),
    'Sinqee': RegExp(r'sinqee|ሲንቄ', caseSensitive: false),
    'Berhan': RegExp(r'berhan|ብርሃን', caseSensitive: false),
    'Abay': RegExp(r'abay\s+bank|አባይ', caseSensitive: false),
  };

  // 1. Direct transfer statements & explicit payment labels
  static final _primaryTransferStatements = <RegExp>[
    // "ETB 200.00 has been debited", "200.00 ETB has been credited", "has been transferred"
    RegExp(
      _cur + _n + r'\s+has\s+been\s+(?:debited|credited|transferred|sent|paid)',
      caseSensitive: false,
    ),
    // "credited with ETB 1,500.00", "debited with ETB 500.00"
    RegExp(
      r'(?:credited|debited)\s+with\s+' + _cur + _n,
      caseSensitive: false,
    ),
    // "received ETB 350.00", "transferred ETB 350.00", "paid ETB 350.00", "sent ETB 350.00"
    RegExp(
      r'(?:received|transferred|paid|sent)\s+' + _cur + _n,
      caseSensitive: false,
    ),
    // "Transferred Amount : 50.00 ETB", "Transfer Amount: 50.00", "Settled Amount: 50.00", "Credited Amount: 50.00"
    RegExp(
      r'(?:transferred\s*amount|transfer\s*amount|settled\s*amount|credited\s*amount|sent\s*amount|received\s*amount|payment\s*amount|net\s*amount|የተላለፈው\s*ገንዘብ|የተላለፈ\s*ሒሳብ|የተከፈለ\s*ገንዘብ|የተላከው)\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
    // "Amount: 200.00 ETB", "Payment: 200.00", "ሒሳብ"
    RegExp(
      r'(?:amount|payment|total\s*(?:amount|payment|paid)?|ጠቅላላ\s*ክፍያ|ሒሳብ|የተከፈለ)\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
  ];

  // Specific fee / charge patterns whose amounts must NEVER be taken as the main payment:
  static final _feePatterns = <RegExp>[
    RegExp(
      r'(?:service\s*(?:charge|fee)|transaction\s*fee|transfer\s*fee|vat(?:\s*\(\d+%\))?|disaster\s*recovery(?:\s*\(\d+%\))?|commission|charge|fee|የአገልግሎት\s*ክፍያ|ቫት|ኮሚሽን)\s*(?:of)?\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
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

    // 2.1 Smart Provider Cross-Check from definitive bank reference prefixes:
    if (reference != null) {
      final refUpper = reference.toUpperCase();
      if (RegExp(r'^(?:DJ|CR)[A-Z0-9]{8}$').hasMatch(refUpper)) {
        provider = 'Telebirr';
      } else if (refUpper.startsWith('FT')) {
        provider = 'CBE';
      } else if (refUpper.startsWith('DA')) {
        provider = 'Dashen';
      } else if (refUpper.startsWith('AW')) {
        provider = 'Awash';
      } else if (refUpper.startsWith('MP')) {
        provider = 'M-Pesa';
      } else if (refUpper.startsWith('CP')) {
        provider = 'Coopay';
      } else if (refUpper.startsWith('SQ')) {
        provider = 'Sinqee';
      } else if (refUpper.startsWith('WG')) {
        provider = 'Wegagen';
      } else if (refUpper.startsWith('HB')) {
        provider = 'Hibret';
      }
    }

    // Additional check for Telebirr SuperApp transfer receipt:
    if (provider == null || provider == 'Other' || provider == 'Zemen') {
      final lower = text.toLowerCase();
      if (lower.contains('transfer money') && (lower.contains('transaction to') || lower.contains('transaction number') || lower.contains('finished'))) {
        provider = 'Telebirr';
      }
    }

    // 3. Detect Amount (Direct transfer extraction without auto-fee subtraction)
    // Collect all explicit fee, VAT, service charge, and tax numbers to exclude them
    final excludedFees = <double>{};
    for (final re in _feePatterns) {
      for (final m in re.allMatches(text)) {
        final f = _num(m.group(1));
        if (f != null) excludedFees.add(f);
      }
    }

    double? amount;

    // Pass 1: Direct transfer / credited / debited / received statements
    for (final re in _primaryTransferStatements) {
      final m = re.firstMatch(text);
      if (m != null) {
        final v = _num(m.group(1));
        if (v != null && !excludedFees.contains(v)) {
          amount = v;
          break;
        }
      }
    }

    // Pass 2: Multi-line label scanning (e.g. line 1: "Transferred Amount", line 2: "200.00 ETB")
    if (amount == null) {
      for (var i = 0; i < lines.length - 1; i++) {
        final cur = lines[i].toLowerCase();
        if (cur.contains('transferred amount') ||
            cur.contains('transfer amount') ||
            cur.contains('settled amount') ||
            cur.contains('received amount') ||
            cur.contains('credited amount') ||
            cur.contains('sent amount') ||
            cur.contains('payment amount') ||
            cur.contains('amount') ||
            cur.contains('total') ||
            cur.contains('የተላለፈው') ||
            cur.contains('ክፍያ')) {
          final next = lines[i + 1];
          final nm = RegExp(r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)').firstMatch(next);
          if (nm != null) {
            final v = _num(nm.group(1));
            if (v != null && !excludedFees.contains(v) && v < 10000000) {
              amount = v;
              break;
            }
          }
        }
      }
    }

    // Pass 3: Standalone currency with ETB / Birr before or after
    if (amount == null) {
      final candidates = <double>[];
      for (final m in _amountCurrencyBefore.allMatches(text)) {
        final v = _num(m.group(1));
        if (v != null && !excludedFees.contains(v) && v < 10000000) candidates.add(v);
      }
      for (final m in _amountCurrencyAfter.allMatches(text)) {
        final v = _num(m.group(1));
        if (v != null && !excludedFees.contains(v) && v < 10000000) candidates.add(v);
      }
      if (candidates.isNotEmpty) {
        amount = candidates.first;
      }
    }

    // Pass 4: Line scanning for standalone signed numbers (e.g. "-100.00" or "+100.00")
    if (amount == null) {
      for (final line in lines) {
        final sm = _standaloneAmountWithSign.firstMatch(line);
        if (sm != null) {
          final v = _num(sm.group(1));
          if (v != null && !excludedFees.contains(v) && v < 10000000) {
            amount = v;
            break;
          }
        }
      }
    }

    // Pass 5: Scan line containing decimals (e.g. "100.00" alone on a line)
    if (amount == null) {
      for (final line in lines) {
        final cleanLine = line.replaceAll(RegExp(r'[^0-9.,]'), '');
        final dm = _standaloneAmountDecimal.firstMatch(cleanLine);
        if (dm != null) {
          final v = _num(dm.group(1));
          if (v != null && !excludedFees.contains(v) && v > 0.5 && v < 5000000 && !line.contains(RegExp(r'202\d|199\d'))) {
            amount = v;
            break;
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
      netAmount: amount,
      fee: null,
      totalPaid: amount,
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

