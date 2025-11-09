import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayService {
  final Razorpay _razorpay = Razorpay();

  Function(PaymentSuccessResponse)? _onSuccess;
  Function(PaymentFailureResponse)? _onError;

  void init() {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void pay({
    required double amount,
    Function(PaymentSuccessResponse)? onSuccess,
    Function(PaymentFailureResponse)? onError,
  }) {
    _onSuccess = onSuccess;
    _onError = onError;
    var options = {
      'key': 'rzp_test_RKBhHHv1UUVxrl',
      'amount': (amount * 100).toInt(), // amount in paise
      'name': 'PC USER',
      'description': 'To pay Cab amount',
      'theme': {'color': '#F37254'}
    };
    _razorpay.open(options);
  }

  void _handleSuccess(PaymentSuccessResponse response) {
    for (var i = 0; i < 10; i++) {
      print("Success");
    }
    print('Payment Success: ${response.paymentId}');
    if (_onSuccess != null) {
      _onSuccess!(response);
    }
  }

  void _handleError(PaymentFailureResponse response) {
    print('Payment Failed: ${response.code} - ${response.message}');
    if (_onError != null) {
      _onError!(response);
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('External Wallet: ${response.walletName}');
  }

  void dispose() {
    _razorpay.clear();
  }
}
