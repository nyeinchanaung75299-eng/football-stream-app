import 'package:flutter/material.dart';

/// Remove every route above the login/AuthGate root, including nested private
/// source pages and modal dialogs. A root-widget rebuild alone cannot remove
/// Navigator routes that were pushed above it.
void closeAdminPrivateRoutes(BuildContext context) {
  Navigator.of(context, rootNavigator: true)
      .popUntil((route) => route.isFirst);
}
