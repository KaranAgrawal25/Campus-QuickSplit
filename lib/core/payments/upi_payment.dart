/// A standards-based UPI payment request.
///
/// This deliberately contains only payment-routing details. It does not
/// contain database IDs, banking credentials, or anything that could imply
/// payment verification.
class UpiPayment {
  const UpiPayment({
    required this.payeeUpiId,
    required this.payeeName,
    required this.amountPaise,
    required this.note,
  });

  final String payeeUpiId;
  final String payeeName;
  final int amountPaise;
  final String note;

  static final RegExp _upiPattern = RegExp(
    r'^[a-zA-Z0-9._-]{2,}@[a-zA-Z0-9.-]{2,}$',
  );

  static bool isValidUpiId(String value) => _upiPattern.hasMatch(value.trim());

  /// Exact decimal representation required by UPI, derived only from the
  /// integer paise value. No floating-point calculation is used.
  static String amountFromPaise(int paise) {
    if (paise <= 0) {
      throw ArgumentError.value(paise, 'paise', 'must be positive');
    }
    final whole = paise ~/ 100;
    final fraction = (paise % 100).toString().padLeft(2, '0');
    return '$whole.$fraction';
  }

  void validate() {
    if (!isValidUpiId(payeeUpiId)) {
      throw ArgumentError('Invalid UPI ID');
    }
    if (payeeName.trim().isEmpty) {
      throw ArgumentError('Payee name is required');
    }
    amountFromPaise(amountPaise);
  }

  /// `upi://pay` URI suitable for compatible Indian UPI applications.
  Uri toUri() {
    validate();
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': payeeUpiId.trim(),
        'pn': payeeName.trim(),
        'am': amountFromPaise(amountPaise),
        'cu': 'INR',
        'tn': note.trim().isEmpty
            ? 'Campus QuickSplit settlement'
            : note.trim(),
      },
    );
  }
}
