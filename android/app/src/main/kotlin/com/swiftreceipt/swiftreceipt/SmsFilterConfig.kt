package com.swiftreceipt.swiftreceipt

/**
 * Native Android SMS Filter Configuration for Mela.
 *
 * HOW TO ADD YOUR OWN CUSTOM FILTER WORDS:
 * - Add bank sender IDs / numbers to [allowedSenders].
 * - Add incoming money keywords to [incomingKeywords].
 * - Add noise/spam/OTP phrases to [ignoredKeywords].
 */
object SmsFilterConfig {

    val allowedSenders = listOf(
        "127",
        "telebirr",
        "ethiotelecom",
        "cbe",
        "cbebirr",
        "cbe birr",
        "889",
        "881",
        "awash",
        "dashen",
        "amole",
        "abyssinia",
        "boa",
        "sinqee",
        "siinqee",
        "wegagen",
        "hibret",
        "berhan",
        "coop",
        "oromia",
        "nib",
        "zemen",
        "enat",
        "global",
        "tsedey",
        "amhara",
        "gadaa",
        "hijra",
        "zamzam",
        "rammis",
        "sidama"
    )

    val incomingKeywords = listOf(
        "received",
        "credited",
        "credit",
        "deposit",
        "deposited",
        "transferred to",
        "transfer to end user",
        "payment received",
        "successful credit",
        "ደርሶዎታል",
        "ገቢ ተደርጓል",
        "ገቢ",
        "ተላልፏል",
        "የግብይት ቁጥር",
        "ሒሳብዎ ገቢ"
    )

    val ignoredKeywords = listOf(
        "otp",
        "verification code",
        "confirmation code",
        "secret code",
        "security code",
        "ይለፍ ቃል",
        "የይለፍ ቃል",
        "የማረጋገጫ ኮድ",
        "airtime bought",
        "bought package",
        "package purchase",
        "data package",
        "voice package",
        "recharge",
        "የአየር ሰዓት",
        "ፓኬጅ ገዝተዋል",
        "you have transferred",
        "transferred from",
        "debited",
        "debit",
        "withdrawn",
        "withdrew",
        "ተቀናሽ",
        "ወጪ"
    )

    fun shouldProcessSms(sender: String, body: String): Boolean {
        val s = sender.trim().lowercase()
        val b = body.trim().lowercase()

        if (b.isEmpty()) return false

        // 1. Block noise / OTP / personal / debit
        for (bad in ignoredKeywords) {
            if (b.contains(bad)) return false
        }

        // 2. Check sender or body contains bank name
        val senderMatches = allowedSenders.any { s.contains(it) || s == it }
        val hasIncoming = incomingKeywords.any { b.contains(it) }

        if (senderMatches) {
            return hasIncoming
        }

        val bodyMentionsBank = allowedSenders.any { b.contains(it) }
        return bodyMentionsBank && hasIncoming
    }
}
