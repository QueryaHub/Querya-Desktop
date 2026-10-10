/// The result a connection form keeps after *Test Connection*: `success`,
/// `failed` (no reason known), `error: <text>` (an unexpected exception), or
/// the reason itself, in the user's terms (#1308).
const connectionTestSuccess = 'success';

/// The line the form shows for [result].
String connectionTestMessage(String result) {
  if (result == connectionTestSuccess) return 'Connection successful!';
  if (result == 'failed') return 'Connection failed';
  if (result.startsWith('error:')) return result.substring(6).trim();
  return result;
}

/// How long the result stays before it dismisses itself: a reason takes
/// longer to read than "Connection successful!".
Duration connectionTestResultLifetime(String result) => result ==
        connectionTestSuccess
    ? const Duration(seconds: 5)
    : const Duration(seconds: 20);
