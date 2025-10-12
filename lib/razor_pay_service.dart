import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayService {
  final Razorpay _razorpay = Razorpay();

  void init() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void pay(
      {required double amount,
      required String email,
      required String contact}) {
    // rzp_test_RKBhHHv1UUVxrl,VbzPvrbPjPu25jFxc931MrPR

    var options = {
      'key': 'rzp_test_RKBhHHv1UUVxrl',
      'amount': (amount * 100).toInt(), // amount in paise
      'name': 'PC USER',
      'description': 'To pay Cab amount',
      'prefill': {'contact': contact, 'email': email},
      'theme': {'color': '#F37254'}
    };
    _razorpay.open(options);
  }

  void _handleSuccess(PaymentSuccessResponse response) {
    print('Payment Success: ${response.paymentId}');
  }

  void _handleError(PaymentFailureResponse response) {
    print('Payment Failed: ${response.code} - ${response.message}');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('External Wallet: ${response.walletName}');
  }

  void dispose() {
    _razorpay.clear();
  }
}
