/// Centralized SMS Filter Configuration for Ethiopian Banks & Mobile Money.
///
/// ---------------------------------------------------------------------------
/// HOW TO ADD YOUR OWN CUSTOM FILTER WORDS:
/// 1. To add a new Bank or Shortcode: Add to [allowedSenders] list below.
/// 2. To add words that identify incoming payments: Add to [incomingKeywords] list.
/// 3. To block annoying spam/promos/OTPs: Add to [ignoredKeywords] list.
/// ---------------------------------------------------------------------------
class SmsFilterConfig {
  SmsFilterConfig._();

  /// Senders (Shortcodes, Bank Names, Fintech IDs) accepted by the system.
  static final List<String> allowedSenders = [
    // Mobile Money & Telco
    '127',
    'telebirr',
    'ethiotelecom',
    'ethio telecom',
    'mpesa',
    'm-pesa',
    'safaricom',

    // Major Commercial Banks & Wallets
    'cbe',
    'cbebirr',
    'cbe birr',
    'commercial bank of ethiopia',
    '889',
    '881',
    '8899',
    'awash',
    'awashbank',
    'dashen',
    'dashenbank',
    'amole',
    'abyssinia',
    'boa',
    'apollo',
    'sinqee',
    'siinqee',
    'siinqeebank',
    'wegagen',
    'wegagenbank',
    'hibret',
    'hibretbank',
    'unitedbank',
    'berhan',
    'berhanbank',
    'coop',
    'coopbank',
    'coopay',
    'coopay-ebirr',
    'oromia',
    'oromiabank',
    'nib',
    'nibbank',
    'zemen',
    'zemenbank',
    'enat',
    'enatbank',
    'global',
    'globalbank',
    'tsedey',
    'tsedeybank',
    'amhara',
    'amharabank',
    'gadaa',
    'gadaabank',
    'hijra',
    'hijrabank',
    'zamzam',
    'zamzambank',
    'rammis',
    'rammisbank',
    'sidama',
    'sidamabank',
    'shabelle',
  ];

  /// Keywords in the SMS text indicating MONEY RECEIVED into the business account.
  static final List<String> incomingKeywords = [
    // English
    'received',
    'credited',
    'credit',
    'deposit',
    'deposited',
    'transferred to your account',
    'transferred into your account',
    'payment received',
    'payment from',
    'successful credit',
    'incoming payment',
    'has been credited',
    'has been credited with',

    // Amharic (Ethiopic)
    'ደርሶዎታል', // received
    'ገቢ ተደርጓል', // credited
    'ገቢ ሆኗል', // credited/deposited
    'ገቢ', // deposit/incoming
    'ሒሳብዎ ገቢ', // your account credited
    'ክፍያ ደርሶዎታል', // payment received

    // Afaan Oromoo
    'galii ta\'eera',
    'galii taheera',
    'herrega keessan',
    'isin ga\'eera',
  ];

  /// Noise keywords to REJECT immediately (OTPs, promos, personal texts, debits/expenses).
  static final List<String> ignoredKeywords = [
    // Security / Auth OTPs
    'otp',
    'verification code',
    'confirmation code',
    'secret code',
    'security code',
    'ይለፍ ቃል',
    'የይለፍ ቃል',
    'የማረጋገጫ ኮድ',

    // Telecom Services / Airtime / Packages
    'airtime bought',
    'bought package',
    'package purchase',
    'data package',
    'voice package',
    'recharge successful',
    'የአየር ሰዓት',
    'ፓኬጅ ገዝተዋል',

    // Outgoing Transactions / Withdrawals / Debits / Transfers Sent
    'you have successfully transferred',
    'you have transferred',
    'successfully transferred',
    'transferred from',
    'transferred out',
    'you transferred',
    'you have successfully paid',
    'you have paid',
    'successfully paid',
    'you paid',
    'payment to',
    'you have sent',
    'you sent',
    'sent to',
    'debited',
    'has been debited',
    'was debited',
    'is debited',
    'withdrawn',
    'withdrew',
    'withdrawal',
    'cash out',
    'cashout',
    'ተቀናሽ ተደርጓል',
    'ተቀናሽ ሆኗል',
    'ተቀናሽ',
    'ወጪ ተደርጓል',
    'ወጪ ሆኗል',
    'ወጪ',
    'አስተላልፈዋል',
    'በተሳካ ሁኔታ አስተላልፈዋል',
    'ከሒሳብዎ ወጪ',
    'ከፍለዋል',
    'ልከዋል',
    'ተልኳል',
    'baasii',
    'ergameera',
    'kan kaffaltan',

    // Promo / Spam
    'congratulations you won',
    'lottery',
    'promo',
  ];

  /// Checks if an SMS represents money leaving the account (debit/transfer out/withdrawal).
  static bool isDebitOrOutgoing(String text) {
    final lower = text.toLowerCase();

    for (final bad in ignoredKeywords) {
      if (lower.contains(bad)) return true;
    }

    final debitRegex = RegExp(
      r'(?:'
      r'you\s+have\s+(?:successfully\s+)?transferred|'
      r'successfully\s+transferred|'
      r'transferred\s+(?:[A-Za-z0-9,\.]+\s+)?from\s+(?:your\s+)?account|'
      r'transferred\s+from|'
      r'you\s+transferred|'
      r'transferred\s+out|'
      r'you\s+have\s+(?:successfully\s+)?paid|'
      r'successfully\s+paid|'
      r'you\s+paid|'
      r'payment\s+to\b|'
      r'you\s+have\s+sent|'
      r'you\s+sent|'
      r'sent\s+to\b|'
      r'\bdebited\b|'
      r'has\s+been\s+debited|'
      r'account\s+debited|'
      r'\bwithdrawn\b|'
      r'\bwithdrew\b|'
      r'\bwithdrawal\b|'
      r'cash\s*out|'
      r'airtime\s+bought|'
      r'package\s+purchase|'
      r'bought\s+package|'
      r'recharge\s+successful|'
      // Amharic
      r'ወጪ\s*(?:ተደርጓል|ሆኗል)?|'
      r'ከ(?:ሒሳብዎ|አካውንትዎ|አካውንት)\s*ወጪ|'
      r'ተቀናሽ\s*(?:ተደርጓል|ሆኗል)?|'
      r'አስተላልፈዋል|'
      r'ከፍለዋል|'
      r'ልከዋል|'
      r'የአየር\s*ሰዓት|'
      r'ፓኬጅ\s*ገዝተዋል|'
      // Afaan Oromoo
      r'\bbaasii\b|'
      r'\bergameera\b|'
      r'kan\s+kaffaltan'
      r')',
      caseSensitive: false,
    );

    return debitRegex.hasMatch(lower);
  }

  /// Checks if an incoming SMS meets all security & business criteria.
  static bool shouldProcessSms({required String sender, required String body}) {
    final s = sender.trim().toLowerCase();
    final b = body.trim().toLowerCase();

    if (b.isEmpty) return false;

    // 1. REJECT if any debit, outgoing transfer, OTP, airtime, or noise is detected
    if (isDebitOrOutgoing(b)) {
      return false;
    }

    // 2. CHECK SENDER MATCH
    final senderMatches = allowedSenders.any((allowed) => s.contains(allowed) || s == allowed);
    final hasBankMention = allowedSenders.any((allowed) => b.contains(allowed));

    if (!senderMatches && !hasBankMention) {
      return false;
    }

    // 3. MUST CONTAIN POSITIVE INCOMING CREDIT KEYWORD
    return incomingKeywords.any((kw) => b.contains(kw));
  }
}
