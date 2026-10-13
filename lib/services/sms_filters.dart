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
    'transferred to',
    'transferred into',
    'transfer to end user',
    'payment received',
    'payment from',
    'successful credit',
    'incoming payment',
    'fund transfer',
    'txn id',
    'transaction number',
    'ref no',
    'reference no',
    'trans ref',

    // Amharic (Ethiopic)
    'ደርሶዎታል', // received
    'ገቢ ተደርጓል', // credited
    'ገቢ ሆኗል', // credited/deposited
    'ገቢ', // deposit/incoming
    'ተላልፏል', // transferred
    'የግብይት ቁጥር', // transaction number
    'ሒሳብዎ ገቢ', // your account credited
    'ክፍያ ደርሶዎታል', // payment received
    'ክፍያ ተፈጽሟል', // payment made
    'የገንዘብ ዝውውር', // money transfer

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
    'confirmation code is',
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

    // Outgoing Transactions / Withdrawals / Debits
    'you have transferred',
    'transferred from',
    'debited',
    'debit',
    'withdrawn',
    'withdrew',
    'cash out',
    'ተቀናሽ ሆኗል',
    'ወጪ ተደርጓል',
    'ወጪ',

    // Promo / Spam
    'congratulations you won',
    'lottery',
    'promo',
  ];

  /// Checks if an incoming SMS meets all security & business criteria.
  static bool shouldProcessSms({required String sender, required String body}) {
    final s = sender.trim().toLowerCase();
    final b = body.trim().toLowerCase();

    if (b.isEmpty) return false;

    // 1. REJECT if any ignore keyword is found
    for (final bad in ignoredKeywords) {
      if (b.contains(bad)) return false;
    }

    // 2. CHECK SENDER MATCH
    final senderMatches = allowedSenders.any((allowed) => s.contains(allowed) || s == allowed);

    // 3. CHECK CONTENT MATCH (In case sender is unknown number but body is signed by a bank)
    final hasIncomingPhrase = incomingKeywords.any((kw) => b.contains(kw));

    if (senderMatches) {
      return hasIncomingPhrase;
    }

    // If sender wasn't matched directly, check if message is clearly signed by a recognized institution
    final hasBankMention = allowedSenders.any((allowed) => b.contains(allowed));
    return hasBankMention && hasIncomingPhrase;
  }
}
