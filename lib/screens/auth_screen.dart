import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

/// Google sign-in screen (Firebase Auth).
/// Shown when no user is signed in. After sign-in, [HomeShell] takes over.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().signInWithGoogle();
      // Auth state stream in main.dart switches to HomeShell automatically.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Login မရပါ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.monitor_heart,
                  size: 72, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text(
                '🩺 ကျန်းမာရေး',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'ကျန်းမာရေး မှတ်တမ်းများ၊ ဆေးဝါးများ၊ အစားအစာနှင့် လေ့ကျင့်ခန်းများကို တစ်နေရာတည်းမှာ စီမံပါ။',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Google နဲ့ ဝင်မယ်'),
              ),
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '🔒 Data တွေကို Firebase server မှာ သိမ်းပါတယ်။ '
                    'Offline မှာ ဖုန်းထဲမှာ သိမ်းထားပြီး online ဖြစ်တာနဲ့ အလိုလို server ကို ပို့ပါတယ်။ '
                    'သင့်ရဲ့ data ကို သင်ကလွဲပြီး ဘယ်သူမှ မြင်လို့မရပါ။',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
