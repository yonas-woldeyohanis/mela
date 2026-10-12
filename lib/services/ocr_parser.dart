/// Client-side robust regex and layout extraction for Ethiopian mobile-money / bank receipts.
class ParsedReceipt {
  const ParsedReceipt({
    this.amount,
    this.reference,
    this.provider,
    this.sender,
    this.receiver,
    this.timeText,
    this.rawText = '',
  });

  final double? amount;
  final String? reference, provider, sender, receiver, timeText;
  final String rawText;

  int get found => [amount, reference, provider].where((e) => e != null).length;
}

class OcrParser {
  static const _n = r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)';
  static const _cur = r'(?:ETB|Birr|Br\.?|ብር)?\s*';

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

  // Explicit label patterns
  static final _amountLabels = <RegExp>[
    // e.g. "Total Paid Amount : 100.00 ETB" or "Transferred Amount: 1,200.00"
    RegExp(
      r'(?:total\s*(?:paid\s*)?amount|transferred\s*amount|transfer\s*amount|paid\s*amount|debited\s*amount|sent\s*amount|settled\s*amount|credited\s*amount|amount|ሒሳብ|የተከፈለ)\s*[:\-]?\s*' +
          _cur +
          _n,
      caseSensitive: false,
    ),
    // e.g. "Payment : 150.00 ETB" or "Total: 100 ETB"
    RegExp(r'(?:payment|total|debit|credit)\s*[:\-]?\s*' + _cur + _n, caseSensitive: false),
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

  // Alphanumeric with mix of digits and letters (e.g. DIO23G4GOE, FT23456ABCDE, etc.)
  static final _refFallback = RegExp(r'\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{8,22}\b');

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

  static ParsedReceipt parse(String raw) {
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

    // 2. Detect Reference Number
    String? reference;
    for (final m in _refLabel.allMatches(text)) {
      final tok = m.group(1)!;
      // Must have at least 1 digit and 1 letter or length >= 8
      if (RegExp(r'\d').hasMatch(tok) && RegExp(r'[A-Za-z]').hasMatch(tok) && tok.length >= 6) {
        reference = tok.toUpperCase();
        break;
      }
    }
    // Fallback if not labeled
    if (reference == null) {
      final matches = _refFallback.allMatches(text.toUpperCase()).map((m) => m.group(0)!).toList();
      for (final candidate in matches) {
        // Exclude dates, phone numbers, or common words
        if (!candidate.startsWith('202') && candidate.length >= 8 && candidate.length <= 20) {
          reference = candidate;
          break;
        }
      }
    }

    // 3. Detect Amount
    double? amount;

    // Pass A: Explicit labels
    for (final re in _amountLabels) {
      final m = re.firstMatch(text);
      if (m != null) {
        final val = _num(m.group(1));
        if (val != null) {
          amount = val;
          break;
        }
      }
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
        // If multiple, exclude astronomical numbers or phone numbers
        final plausible = candidates.where((c) => c < 10000000).toList();
        if (plausible.isNotEmpty) {
          amount = plausible.first; // usually the first marked currency amount is the transaction total
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
        // Check if the line is primarily a decimal number (like 100.00)
        final cleanLine = line.replaceAll(RegExp(r'[^0-9.,]'), '');
        final dm = _standaloneAmountDecimal.firstMatch(cleanLine);
        if (dm != null) {
          final v = _num(dm.group(1));
          // Avoid dates like 2026.10 or phone numbers
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
      reference: reference,
      provider: provider,
      sender: sender?.isEmpty == true ? null : sender,
      receiver: receiver?.isEmpty == true ? null : receiver,
      timeText: time,
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

