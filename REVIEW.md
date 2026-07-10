# Code Review — `starter/lib/sms_console.dart`

Reviewed by: Arman
File: `starter/lib/sms_console.dart` 
Total findings: **12**

---

## Quick Summary — What Would Happen If This Goes Live

Before going into detail, here is what would actually break for real users and the business:

1. **API key is exposed in the code.** Anyone who can see this repo can steal it and use the company's SMS quota for free.
2. **Every API call fails with 403.** The required `X-Tenant-Id` header is missing, so the backend rejects all requests.
3. **The app crashes** when it tries to read a decimal string `"12.4500"` as a `double`. This throws a `TypeError` at runtime.
4. **Infinite network requests.** There is an HTTP call inside `FutureBuilder` which is inside `build()`. Every time the screen redraws, a new network request fires. This loops forever.

---

## Finding 1 — API Key and Tenant ID Hardcoded in Source Code

**Severity:** Critical
**Lines:** 9–10

**What is wrong:**
The file has real production credentials written directly in the code:
```dart
const String kApiKey = 'fw_live_8c21e0b47ad94f13ba77e0c9d51a3b62';
const String kTenantId = '9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f';
```
If this code is pushed to GitHub (even a private repo that later becomes public, or gets accessed by a third party), anyone can read these credentials, log in as this tenant, send SMS messages at the company's expense, or view private message history.

**How to fix:**
Never put secrets in source code. Load them at build time using `--dart-define` or `--dart-define-from-file`, or store them in `flutter_secure_storage` and load at runtime. The source code should have no hardcoded secrets.

---

## Finding 2 — Missing `X-Tenant-Id` Header on All API Calls

**Severity:** Critical
**Lines:** 48, 74, 127

**What is wrong:**
According to the API contract, every request must include two headers:
```
Authorization: Bearer <token>
X-Tenant-Id: <uuid>
```
The code sends only `Authorization`. The `X-Tenant-Id` header is completely missing from all three HTTP calls. The backend will return `403 Forbidden` for every request, so nothing in the app will work at all.

**How to fix:**
Add the `X-Tenant-Id` header to every request:
```dart
headers: {
  'Authorization': 'Bearer $kApiKey',
  'X-Tenant-Id': currentTenantId,
  'Content-Type': 'application/json',
}
```

---

## Finding 3 — Decimal String Cast to `double` Causes App Crash + Wrong Billing Math

**Severity:** Critical
**Lines:** 13, 53–56, 83–85, 122

**What is wrong — two separate problems:**

**Problem A (crash):** The API returns money as a decimal string like `"12.4500"`. The code does:
```dart
total = total + (costRows[i]['totalCost'] as double);
```
You cannot cast a `String` to `double` this way. This throws a `_TypeError` at runtime and the app crashes immediately when loading cost data.

**Problem B (wrong numbers):** Even if the cast worked, using `double` for money is wrong. Binary floating-point cannot represent some decimals exactly. For example, `0.1 + 0.2` gives `0.30000000000000004` in Dart, not `0.3`. With rates like `0.0079` across thousands of messages, this adds up to real billing errors on real invoices.

**How to fix:**
Parse the decimal string correctly. Use the `decimal` package or represent money as integer minor units (e.g., `int microCents` where 1 unit = 10000 micro-units). Never use `double` for money.

---

## Finding 4 — Infinite Network Loop Inside `FutureBuilder`

**Severity:** High
**Lines:** 124–147

**What is wrong:**
Inside the `build()` method, there is a `FutureBuilder` that creates a new HTTP request every time it builds:
```dart
FutureBuilder(
  future: http.get(Uri.parse('$kApiBase/api/v1/sms/cost/breakdown'), ...),
  ...
)
```
Flutter calls `build()` many times — when the keyboard opens, when state changes, when the parent rebuilds. Each call to `build()` creates a brand new `http.get()` call. The server gets hit with requests in a loop. This wastes battery, wastes network data, can trigger rate limiting (`429`), and loads the server unnecessarily.

**How to fix:**
Move the `http.get()` call out of `build()`. Store the `Future` in a variable that is created only once (for example, in `initState()` or in a state management provider). The `FutureBuilder` should reference that stored future, not create a new one each time.

---

## Finding 5 — Phone Number and Message Body Printed to Console Logs

**Severity:** High
**Line:** 69

**What is wrong:**
```dart
print('Sending SMS to $phone: $body');
```
This prints the user's real phone number and the full SMS message body to the debug console. In production, this output can be collected by crash reporting tools like Firebase Crashlytics, device log aggregators, or CI/CD pipelines — all of which can store these personal details. This is a GDPR and privacy violation.

**How to fix:**
Remove the `print` statement. If logging is needed for debugging, use a structured logger that is disabled in release builds, and never include PII (personal information like phone numbers or message content) in logs.

---

## Finding 6 — Wrong API Used for Message History (Shows Wrong Data)

**Severity:** High
**Line:** 140

**What is wrong:**
The list widget tries to display `rows[i]['recipient']` from the cost breakdown endpoint:
```dart
subtitle: Text(rows[i]['recipient']),
```
But the `/api/v1/sms/cost/breakdown` endpoint does not return any `recipient` field. It only returns provider names, total costs, and message counts. There are no recipients here. The `recipient` field comes from the message history endpoint (`GET /api/v1/sms/messages`).

So the UI will either show `null` or crash trying to read a field that does not exist.

**How to fix:**
Separate the two concerns. Use `/api/v1/sms/cost/breakdown` only for the billing table. Use `GET /api/v1/sms/messages` for the message history list. The recipient (which arrives already masked like `+4915*****78`) should only come from the messages endpoint.

---

## Finding 7 — `setState` Called After Widget is Unmounted (Crash on Navigation)

**Severity:** High
**Lines:** 60, 95

**What is wrong:**
Both `loadCosts()` and `sendSms()` do `setState()` after awaiting a network request. If the user navigates away from this screen while the network request is still running, the widget gets unmounted. Then when the response arrives, `setState()` is called on a widget that no longer exists. This throws:
```
setState() called after dispose()
```
This crashes the app or causes unpredictable behavior.

**How to fix:**
Before any `setState()` after an `await`, check if the widget is still mounted:
```dart
if (!mounted) return;
setState(() => loading = false);
```
Or better, move business logic out of the widget entirely into a state management solution like BLoC or Riverpod.

---

## Finding 8 — No Error Handling or Recovery UI

**Severity:** High
**Lines:** 44–61, 71–79, 124–147

**What is wrong — three separate gaps:**

1. `loadCosts()` has no `try/catch`. If the server is down or returns a 500 or 502, the method throws an unhandled exception, `loading` is never set to `false`, and the user sees a spinner forever with no way to retry.

2. `sendSms()` does have a `try/catch`, but it only stores the error in `AppState.lastError`. That error is never shown to the user anywhere in the UI.

3. The `FutureBuilder` only checks `snapshot.hasData`. It does not check `snapshot.hasError`. If the network request fails, the builder falls into an unhandled state.

**How to fix:**
Wrap all HTTP calls in `try/catch`. Handle all error types: network errors, 429 rate limits, 502 gateway errors, 403 auth errors. Show a clear error message in the UI with a "Try Again" button so the user can recover without restarting the app.

---

## Finding 9 — Segment Count Hardcoded, Cost Calculated Locally

**Severity:** Medium
**Lines:** 18–23, 82–83

**What is wrong:**
After sending an SMS, the code calculates the cost itself:
```dart
final segments = 1;
final cost = rateFor(provider) * segments;
```
Two problems here. First, `segments` is always `1` — but SMS messages longer than 160 characters split into multiple segments, each charged separately. Second, provider rates change over time. Hardcoding them client-side means the local calculation will be wrong whenever rates change.

The API already returns the correct `cost` and `segmentCount` in the send response. There is no reason to calculate locally.

**How to fix:**
Read `cost` and `segmentCount` directly from the API response:
```dart
final cost = result['cost'];         // decimal string from server
final segments = result['segmentCount'];  // actual segment count
```

---

## Finding 10 — Cost Breakdown Called Without Required Date Parameters

**Severity:** Medium
**Lines:** 47, 126

**What is wrong:**
The API contract requires `from` and `to` ISO 8601 date parameters for the cost breakdown endpoint:
```
GET /api/v1/sms/cost/breakdown?from=<iso8601>&to=<iso8601>
```
The code calls the endpoint without these parameters:
```dart
Uri.parse('$kApiBase/api/v1/sms/cost/breakdown')
```
Without these query parameters, the backend will return `400 Bad Request`, or return incorrect data without proper date filtering.

**How to fix:**
Always include the date range in the request. A good default is the current month:
```dart
final now = DateTime.now();
final from = DateTime(now.year, now.month, 1).toUtc().toIso8601String();
final to = now.toUtc().toIso8601String();
Uri.parse('$kApiBase/api/v1/sms/cost/breakdown?from=$from&to=$to')
```

---

## Finding 11 — Global Mutable State (`AppState`) is Not Thread-Safe

**Severity:** Medium
**Lines:** 12–16

**What is wrong:**
The code uses a global static class to share state across the app:
```dart
class AppState {
  static double totalCost = 0.0;
  static List<dynamic> history = [];
  static String? lastError;
}
```
This is a global singleton mutated from multiple asynchronous callbacks (`loadCosts` and `sendSms`). In a multi-tenant scenario, there is no isolation between tenants — switching tenants does not clear `AppState`, so data from one tenant can be visible under another. Also, `List<dynamic>` holds raw, untyped API data, which means any access is unsafe and error-prone.

**How to fix:**
Replace global state with a proper state management solution. Each tenant context should have its own scoped state that is fully cleared when switching tenants.

---

## Finding 12 — No Token Expiry or Refresh Handling

**Severity:** Medium
**Lines:** 48, 74, 127

**What is wrong:**
The API contract states that tokens are short-lived (15 minutes) and must be refreshed using `POST /api/v1/auth/refresh`. The code uses a hardcoded API key with no concept of token expiry or refresh at all. When the token expires (in a real scenario), all requests will fail with `403`, and the user will be stuck with no recovery path — not even an error message.

**How to fix:**
Implement token lifecycle management. Store the access token and a refresh token separately. When a `403` response with `errorCode: TOKEN_EXPIRED` is received, automatically call `POST /api/v1/auth/refresh`, store the new token, and retry the original request. The user should never see this happening.

---

## Summary Table

| # | Finding | Severity | Lines |
|---|---|---|---|
| 1 | API key hardcoded in source | Critical | 9–10 |
| 2 | Missing `X-Tenant-Id` header | Critical | 48, 74, 127 |
| 3 | Decimal string cast to `double` — crash + wrong billing | Critical | 53–56, 83–85 |
| 4 | HTTP call inside `FutureBuilder` — infinite loop | High | 124–147 |
| 5 | Phone number and message body in `print` logs | High | 69 |
| 6 | Wrong endpoint used for message history | High | 140 |
| 7 | `setState` after unmount — app crash | High | 60, 95 |
| 8 | No error handling or recovery UI | High | 44–61, 71–79 |
| 9 | Segment count hardcoded, local cost calculation | Medium | 18–23, 82–83 |
| 10 | Cost breakdown missing required date parameters | Medium | 47, 126 |
| 11 | Global mutable state — not tenant-safe | Medium | 12–16 |
| 12 | No token expiry or refresh handling | Medium | 48, 74, 127 |
