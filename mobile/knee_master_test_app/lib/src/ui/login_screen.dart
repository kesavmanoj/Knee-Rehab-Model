import 'package:flutter/material.dart';

import '../models/app_role.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onSignUp,
    this.errorMessage,
    this.infoMessage,
    this.isBusy = false,
  });

  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function({
    required String email,
    required String password,
    required String displayName,
    required AppRole role,
  }) onSignUp;
  final String? errorMessage;
  final String? infoMessage;
  final bool isBusy;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _signUpMode = false;
  AppRole _selectedRole = AppRole.patient;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_signUpMode) {
      await widget.onSignUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
        role: _selectedRole,
      );
      return;
    }

    await widget.onLogin(
      _emailController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final title = _signUpMode ? 'Create Account' : 'Sign In';
    final subtitle = _signUpMode
        ? 'Create a patient or doctor account directly in the app.'
        : 'Sign in with your patient or doctor account.';
    final buttonLabel = _signUpMode ? 'Create account' : 'Sign in';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Knee Rehab Monitor',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 24),
                              if (_signUpMode) ...<Widget>[
                                TextFormField(
                                  controller: _displayNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Display name',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    if (_signUpMode && (value?.trim().isEmpty ?? true)) {
                                      return 'Enter a display name.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<AppRole>(
                                  initialValue: _selectedRole,
                                  decoration: const InputDecoration(
                                    labelText: 'Account type',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const <DropdownMenuItem<AppRole>>[
                                    DropdownMenuItem(
                                      value: AppRole.patient,
                                      child: Text('Patient'),
                                    ),
                                    DropdownMenuItem(
                                      value: AppRole.doctor,
                                      child: Text('Doctor'),
                                    ),
                                  ],
                                  onChanged: widget.isBusy
                                      ? null
                                      : (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedRole = value;
                                          });
                                        },
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty || !text.contains('@')) {
                                    return 'Enter a valid email.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final text = value ?? '';
                                  if (text.isEmpty) {
                                    return 'Enter your password.';
                                  }
                                  if (_signUpMode && text.length < 6) {
                                    return 'Password must be at least 6 characters.';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              if (widget.errorMessage != null) ...<Widget>[
                                const SizedBox(height: 16),
                                Text(
                                  widget.errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                              if (widget.infoMessage != null) ...<Widget>[
                                const SizedBox(height: 16),
                                Text(
                                  widget.infoMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: widget.isBusy ? null : _submit,
                                  child: Text(widget.isBusy ? 'Please wait...' : buttonLabel),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: widget.isBusy
                                      ? null
                                      : () {
                                          setState(() {
                                            _signUpMode = !_signUpMode;
                                          });
                                        },
                                  child: Text(
                                    _signUpMode
                                        ? 'Already have an account? Sign in'
                                        : 'Need an account? Create one',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
