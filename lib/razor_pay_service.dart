import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayService {
  final Razorpay _razorpay = Razorpay();

  void init() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void pay({required double amount, required String email, required String contact}) {
    var options = {
      'key': 'YOUR_KEY_ID',
      'amount': (amount * 100).toInt(), // amount in paise
      'name': 'Your App Name',
      'description': 'Payment Description',
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
