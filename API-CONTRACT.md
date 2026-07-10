# SMS Channel API — contract

The backend is a multi-tenant Spring Boot service. You build against this
contract; you do **not** need our backend running. Stub it however you like
(a local mock server, `http` interceptors, recorded fixtures — your call, and
your choice is part of what we assess).

Base URL is configured per environment. Every request is scoped to a tenant.

## Auth & tenancy

```
Authorization: Bearer <access-token>
X-Tenant-Id:   <uuid>
```

Both headers are required on every call. A request without `X-Tenant-Id`, or
with a tenant the token does not grant, returns `403`.

Tokens are short-lived (15 min) and refreshed at `POST /api/v1/auth/refresh`
with a refresh token. Treat both as credentials.

## `POST /api/v1/sms/send`

```jsonc
// request
{ "to": "+4915112345678", "body": "Your code is 123456", "referenceId": "opt-1" }

// 202 Accepted
{
  "messageId": "SM3fa85f64",
  "provider": "TWILIO",
  "status": "ACCEPTED",          // ACCEPTED | SENT | DELIVERED | FAILED
  "segmentCount": 2,             // an SMS may span multiple segments
  "cost": "0.1500",              // decimal STRING, never a float
  "currency": "EUR"
}

// 400 — validation
{ "errorCode": "INVALID_PHONE_NUMBER", "message": "must be E.164" }
// 429 — rate limited, Retry-After header in seconds
// 502 — upstream provider failed
```

## `POST /api/v1/sms/bulk`

Body: `{ "messages": [ ...SmsMessage ] }`. Returns `207 Multi-Status` with a
per-message result array — **some may succeed while others fail.**

## `GET /api/v1/sms/cost/breakdown?from=<iso8601>&to=<iso8601>`

```jsonc
{
  "currency": "EUR",
  "totalCost": "12.4500",
  "rows": [
    { "provider": "TWILIO",  "totalCost": "8.2500", "messageCount": 110 },
    { "provider": "AWS_SNS", "totalCost": "4.2000", "messageCount": 91  }
  ]
}
```

Note what is **not** here: recipient phone numbers. The cost endpoint never
returns them. If your UI shows a phone number on this screen, it invented it.

## `GET /api/v1/sms/messages?cursor=<opaque>&limit=50`

Cursor-paginated message history.

```jsonc
{
  "items": [
    { "messageId": "SM3fa85f64", "recipient": "+4915*****78",
      "status": "DELIVERED", "segmentCount": 2, "cost": "0.1500",
      "sentAt": "2026-07-09T08:14:22Z" }
  ],
  "nextCursor": "eyJvZmZzZXQiOjUwfQ"   // null when exhausted
}
```

Recipients arrive **already masked**. Do not unmask, and do not log them.

## Money

All monetary values are **decimal strings**. Rates run to four decimal places
(`0.0079`). Do not parse them into `double`. Rounding a fraction of a cent per
message, across hundreds of thousands of messages, is a real number on a real
invoice.

## Delivery status

Status is not final at send time. `ACCEPTED` means the provider took it, not
that it arrived. Status advances asynchronously; the client must be able to
reflect a message moving `ACCEPTED → SENT → DELIVERED` or `→ FAILED` after the
fact.
