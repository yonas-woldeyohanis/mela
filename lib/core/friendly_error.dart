import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Translates technical stack traces, database codes, and socket logs
/// into friendly, human-readable messages for non-technical users.
class FriendlyError {
  FriendlyError._();

  static String toMessage(dynamic error) {
    if (error == null) return 'An unexpected error occurred.';

    final raw = error.toString().toLowerCase();

    // 1. Network & Connectivity issues
    if (error is SocketException ||
        raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('no address associated with hostname') ||
        raw.contains('realtimesubscribeexception') ||
        raw.contains('timedout') ||
        raw.contains('os error') ||
        raw.contains('errno =') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection refused') ||
        raw.contains('clientexception') ||
        raw.contains('handshake') ||
        raw.contains('timeout')) {
      return 'No internet connection. Please check your Wi-Fi or mobile data and try again.';
    }

    // 2. Supabase Auth Exceptions
    if (error is AuthException || raw.contains('authexception')) {
      if (raw.contains('invalid login credentials') || raw.contains('invalid_grant')) {
        return 'Incorrect email or password. Please verify and try again.';
      }
      if (raw.contains('user already registered') || raw.contains('already exists')) {
        return 'An account with this email address is already registered.';
      }
      if (raw.contains('email not confirmed')) {
        return 'Please confirm your email address before signing in.';
      }
      if (raw.contains('jwt expired') || raw.contains('token is expired')) {
        return 'Your session has expired. Please sign in again to continue.';
      }
      if (raw.contains('password should be at least')) {
        return 'Password must be at least 6 characters long.';
      }
      return 'Authentication failed. Please check your credentials and try again.';
    }

    // 3. Supabase Postgrest / Database Exceptions
    if (error is PostgrestException || raw.contains('postgrestexception')) {
      if (raw.contains('duplicate key') || raw.contains('23505')) {
        return 'This record already exists in the system.';
      }
      if (raw.contains('access denied') || raw.contains('permission denied') || raw.contains('42501')) {
        return 'Access denied. You do not have permission to perform this action.';
      }
      if (raw.contains('foreign key') || raw.contains('violates foreign key')) {
        return 'Cannot complete this action because related items still depend on it.';
      }
      return 'Could not complete the request. Please try again in a moment.';
    }

    // 4. Local Biometrics / PIN
    if (raw.contains('notavailable') || raw.contains('not_enrolled')) {
      return 'Biometric authentication is not set up on this device.';
    }
    if (raw.contains('passcode') || raw.contains('pin incorrect')) {
      return 'The PIN you entered is incorrect. Please try again.';
    }

    // 5. Clean common prefixes
    String cleaned = error.toString();
    if (cleaned.startsWith('Exception: ')) {
      cleaned = cleaned.substring('Exception: '.length);
    }
    // If the message is already short and human, return it
    if (cleaned.length < 80 && !cleaned.contains('{') && !cleaned.contains('_')) {
      return cleaned;
    }

    return 'Something went wrong. Please check your connection and try again.';
  }

  /// Displays a modern, non-intrusive floating feedback banner.
  static void show(
    BuildContext context,
    dynamic error, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;
    final msg = toMessage(error);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF1E293B), // Deep slate
        duration: duration,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    msg,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Displays a friendly success banner.
  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF0F172A),
        duration: duration,
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
