/// Utility functions for validating email addresses.
class EmailValidator {
  /// Regular expression pattern for validating email addresses
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Validates a single email address
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;
    return _emailRegex.hasMatch(email);
  }

  /// Validates a comma-separated list of email addresses
  /// Returns true if all emails are valid, false otherwise
  static bool isValidEmailList(String emailList) {
    if (emailList.isEmpty) return true; // Empty field is valid
    
    final emails = emailList.split(',').map((e) => e.trim()).toList();
    return emails.every(isValidEmail);
  }

  /// Validates a comma-separated list of email addresses and returns
  /// detailed information about which ones are invalid
  static Map<String, List<String>> validateEmailListWithDetails(String emailList) {
    if (emailList.isEmpty) {
      return {'valid': [], 'invalid': []};
    }
    
    final emails = emailList.split(',').map((e) => e.trim()).toList();
    final validEmails = <String>[];
    final invalidEmails = <String>[];
    
    for (final email in emails) {
      if (email.isNotEmpty && isValidEmail(email)) {
        validEmails.add(email);
      } else if (email.isNotEmpty) {
        invalidEmails.add(email);
      }
    }
    
    return {'valid': validEmails, 'invalid': invalidEmails};
  }
}