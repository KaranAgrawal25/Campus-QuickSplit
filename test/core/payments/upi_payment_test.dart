import 'package:campus_quicksplit/core/payments/upi_payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payment = UpiPayment(
    payeeUpiId: 'rahul@upi',
    payeeName: 'Rahul Sharma',
    amountPaise: 100025,
    note: 'Campus QuickSplit settlement',
  );

  test('creates an exact standards-based UPI URI', () {
    final uri = payment.toUri();
    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters['pa'], 'rahul@upi');
    expect(uri.queryParameters['pn'], 'Rahul Sharma');
    expect(uri.queryParameters['am'], '1000.25');
    expect(uri.queryParameters['cu'], 'INR');
    expect(uri.queryParameters['tn'], 'Campus QuickSplit settlement');
  });

  test('converts paise to UPI amounts without floating point', () {
    expect(UpiPayment.amountFromPaise(100000), '1000.00');
    expect(UpiPayment.amountFromPaise(1), '0.01');
    expect(UpiPayment.amountFromPaise(109), '1.09');
  });

  test('rejects invalid UPI IDs and non-positive amounts', () {
    expect(UpiPayment.isValidUpiId('rahul@upi'), isTrue);
    expect(UpiPayment.isValidUpiId('not a upi id'), isFalse);
    expect(
      () => const UpiPayment(
        payeeUpiId: 'bad id',
        payeeName: 'Rahul',
        amountPaise: 100,
        note: 'Test',
      ).toUri(),
      throwsArgumentError,
    );
    expect(() => UpiPayment.amountFromPaise(0), throwsArgumentError);
    expect(() => UpiPayment.amountFromPaise(-1), throwsArgumentError);
  });
}
