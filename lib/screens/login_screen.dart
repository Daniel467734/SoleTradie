import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String? error;

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    
    if (email.isEmpty) {
      setState(() => error = 'Please enter your email');
      return;
    }
    if (password.isEmpty) {
      setState(() => error = 'Please enter your password');
      return;
    }
    
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      widget.onLoginSuccess();
    } on FirebaseAuthException catch (e) {
      setState(() => error = '${e.code}: ${e.message}');
      print('FirebaseAuthException during login: code=${e.code}, message=${e.message}');
    } catch (e, st) {
      setState(() => error = e.toString());
      print('Unknown error during login: $e\n$st');
    }
  }

  Future<void> _register() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    
    if (email.isEmpty) {
      setState(() => error = 'Please enter your email');
      return;
    }
    if (password.isEmpty) {
      setState(() => error = 'Please enter your password');
      return;
    }
    if (password.length < 6) {
      setState(() => error = 'Password must be at least 6 characters');
      return;
    }
    
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      widget.onLoginSuccess();
    } on FirebaseAuthException catch (e) {
      setState(() => error = '${e.code}: ${e.message}');
      // Print full stack for debugging
      print('FirebaseAuthException during register: code=${e.code}, message=${e.message}');
    } catch (e, st) {
      setState(() => error = e.toString());
      print('Unknown error during register: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'Enter your email address',
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() => error = null),
            ),
            const SizedBox(height: 16),
            TextField(textCapitalization: TextCapitalization.sentences, 
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your password',
              ),
              obscureText: true,
              onChanged: (_) => setState(() => error = null),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!, 
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _login,
              child: const Text('Login'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _register,
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}