class Receipt {
  const Receipt({
    required this.localId,
    required this.orgId,
    required this.waiterId,
    required this.amount,
    required this.reference,
    required this.createdAt,
    this.tableNumber,
    this.provider,
    this.sender,
    this.receiptTime,
    this.imagePath,
    this.imageUrl,
    this.syncStatus = 'pending',
    this.verificationStatus = 'awaiting',
    this.isFlagged = false,
  });

  final String localId, orgId, waiterId, reference, syncStatus, verificationStatus;
  final String? tableNumber, provider, sender, receiptTime, imagePath, imageUrl;
  final double amount;
  final bool isFlagged;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'local_id': localId,
        'org_id': orgId,
        'waiter_id': waiterId,
        'table_number': tableNumber,
        'amount': amount,
        'reference_number': reference,
        'payment_provider': provider,
        'sender_name': sender,
        'receipt_time': receiptTime,
        'image_path': imagePath,
        'image_url': imageUrl,
        'sync_status': syncStatus,
        'verification_status': verificationStatus,
        'is_flagged': isFlagged ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Receipt.fromMap(Map<String, Object?> m) => Receipt(
        localId: m['local_id'] as String,
        orgId: m['org_id'] as String,
        waiterId: m['waiter_id'] as String,
        tableNumber: m['table_number'] as String?,
        amount: (m['amount'] as num).toDouble(),
        reference: m['reference_number'] as String,
        provider: m['payment_provider'] as String?,
        sender: m['sender_name'] as String?,
        receiptTime: m['receipt_time'] as String?,
        imagePath: m['image_path'] as String?,
        imageUrl: m['image_url'] as String?,
        syncStatus: m['sync_status'] as String,
        verificationStatus: (m['verification_status'] as String?) ?? 'awaiting',
        isFlagged: (m['is_flagged'] as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  Map<String, dynamic> toCloud(String? cloudImagePath) => {
        'local_id': localId,
        'org_id': orgId,
        'waiter_id': waiterId,
        'table_number': tableNumber,
        'amount': amount,
        'reference_number': reference,
        'payment_provider': provider,
        'sender_name': sender,
        'image_url': cloudImagePath,
        'sync_status': 'synced',
        'verification_status': verificationStatus,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

class CloudTx {
  const CloudTx({
    required this.id,
    required this.waiterId,
    required this.amount,
    required this.reference,
    required this.createdAt,
    this.tableNumber,
    this.provider,
    this.sender,
    this.imageUrl,
    this.verificationStatus = 'awaiting',
    this.isFlagged = false,
    this.flagResolved = false,
  });

  final String id, waiterId, reference;
  final String? tableNumber, provider, sender, imageUrl;
  final double amount;
  final String verificationStatus; // verified, mismatch, awaiting, unverified
  final bool isFlagged, flagResolved;
  final DateTime createdAt;

  bool get needsAttention => (isFlagged || verificationStatus == 'mismatch') && !flagResolved;
  bool get isVerified => verificationStatus == 'verified';

  factory CloudTx.fromJson(Map<String, dynamic> j) => CloudTx(
        id: j['id'] as String,
        waiterId: j['waiter_id'] as String,
        amount: (j['amount'] as num).toDouble(),
        reference: j['reference_number'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        tableNumber: j['table_number'] as String?,
        provider: j['payment_provider'] as String?,
        sender: j['sender_name'] as String?,
        imageUrl: j['image_url'] as String?,
        verificationStatus: (j['verification_status'] as String?) ?? 'awaiting',
        isFlagged: j['is_flagged'] == true,
        flagResolved: j['flag_resolved'] == true,
      );
}


class AppUser {
  const AppUser({
    required this.id,
    required this.orgId,
    required this.fullName,
    required this.role,
    required this.orgName,
    required this.joinCode,
    this.orgStatus = 'active',
    this.subscriptionExpiresAt,
  });

  final String id, orgId, fullName, role, orgName, joinCode;
  final String orgStatus;
  final DateTime? subscriptionExpiresAt;

  bool get isSuperAdmin => role == 'super_admin';
  bool get isManager => role == 'manager' || role == 'owner' || role == 'super_admin';
  bool get isOwner => role == 'owner' || role == 'super_admin';
  bool get isSuspended =>
      !isSuperAdmin &&
      (orgStatus == 'suspended' ||
          orgStatus == 'expired' ||
          orgStatus == 'paused' ||
          (subscriptionExpiresAt != null && subscriptionExpiresAt!.isBefore(DateTime.now())));

  Map<String, dynamic> toJson() => {
        'id': id,
        'org_id': orgId,
        'full_name': fullName,
        'role': role,
        'org_name': orgName,
        'join_code': joinCode,
        'org_status': orgStatus,
        'expires_at': subscriptionExpiresAt?.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        orgId: j['org_id'] as String,
        fullName: j['full_name'] as String,
        role: j['role'] as String,
        orgName: j['org_name'] as String,
        joinCode: j['join_code'] as String,
        orgStatus: (j['org_status'] as String?) ?? 'active',
        subscriptionExpiresAt: j['expires_at'] != null ? DateTime.tryParse(j['expires_at'] as String) : null,
      );
}

class TenantOverview {
  const TenantOverview({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.status,
    required this.subscriptionFee,
    this.expiresAt,
    this.contactPhone,
    this.contactPerson,
    this.ownerEmail,
    this.ownerId,
    this.staffCount = 0,
    this.txCount = 0,
    this.totalRevenue = 0.0,
    this.createdAt,
  });

  final String id, name, joinCode, status;
  final double subscriptionFee;
  final DateTime? expiresAt, createdAt;
  final String? contactPhone, contactPerson, ownerEmail, ownerId;
  final int staffCount, txCount;
  final double totalRevenue;

  bool get isExpired => status == 'expired' || (expiresAt != null && expiresAt!.isBefore(DateTime.now()));
  bool get isSuspended => status == 'suspended';
  bool get isPaused => status == 'paused';
  bool get isActive => (status == 'active' || status == 'trial') && !isExpired;
  int get daysRemaining => expiresAt != null ? expiresAt!.difference(DateTime.now()).inDays : 0;
  bool get isDueSoon => isActive && expiresAt != null && daysRemaining <= 3 && daysRemaining >= 0;
  bool get isOverdue => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory TenantOverview.fromJson(Map<String, dynamic> j) => TenantOverview(
        id: j['id'] as String,
        name: j['name'] as String,
        joinCode: (j['join_code'] as String?) ?? '',
        status: (j['status'] as String?) ?? 'active',
        subscriptionFee: (j['subscription_fee'] as num?)?.toDouble() ?? 1000.0,
        expiresAt: j['expires_at'] != null ? DateTime.tryParse(j['expires_at'] as String) : null,
        createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'] as String) : null,
        contactPhone: j['contact_phone'] as String?,
        contactPerson: j['contact_person'] as String?,
        ownerEmail: j['owner_email'] as String?,
        ownerId: j['owner_id'] as String?,
        staffCount: (j['staff_count'] as num?)?.toInt() ?? 0,
        txCount: (j['tx_count'] as num?)?.toInt() ?? 0,
        totalRevenue: (j['total_revenue'] as num?)?.toDouble() ?? 0.0,
      );
}

class Staff {
  const Staff({required this.id, required this.fullName, required this.role});
  final String id, fullName, role;
  factory Staff.fromJson(Map<String, dynamic> j) =>
      Staff(id: j['id'] as String, fullName: j['full_name'] as String, role: j['role'] as String);
}

class AuditRow {
  const AuditRow({
    required this.date,
    required this.digital,
    required this.pos,
    required this.cash,
    required this.difference,
    this.note,
  });
  final DateTime date;
  final double digital, pos, cash, difference;
  final String? note;
  factory AuditRow.fromJson(Map<String, dynamic> j) => AuditRow(
        date: DateTime.parse(j['business_date'] as String),
        digital: (j['digital_total'] as num).toDouble(),
        pos: (j['pos_total'] as num).toDouble(),
        cash: (j['cash_total'] as num).toDouble(),
        difference: (j['difference'] as num).toDouble(),
        note: j['note'] as String?,
      );
}
