# WhatsApp Integration (WAHA)

WAHA (WhatsApp HTTP API) enables WhatsApp messaging without Meta Business API.

## How It Works

WAHA runs a headless WhatsApp Web instance. You link your phone just like you would link WhatsApp Web on a computer.

```
Your Phone (WhatsApp)
        ↕ (linked)
WAHA Container (WhatsApp Web)
        ↕ (HTTP API)
n8n Workflows
```

## Setup

### 1. Start WAHA

```bash
make up
# or just WAHA:
docker compose up -d waha
```

### 2. Access Dashboard

Open http://localhost:3000/dashboard

Login:
- Username: value of `WAHA_USER` in `.env`
- Password: value of `WAHA_PASSWORD` in `.env`

### 3. Link Your Phone

1. Click "Start New Session" (or session may auto-start as "default")
2. You'll see a QR code
3. On your phone: WhatsApp → Settings → Linked Devices → Link a Device
4. Scan the QR code
5. Wait for "CONNECTED" status

### 4. Test

```bash
# Replace with a real number (no + prefix, just digits)
curl -X POST http://localhost:3000/api/sendText \
  -H "Content-Type: application/json" \
  -d '{
    "session": "default",
    "chatId": "385911234567@c.us",
    "text": "Test message from WAHA!"
  }'
```

## n8n Integration

### Install WAHA Node

1. Go to n8n → Settings → Community nodes
2. Install: `@devlikeapro/n8n-nodes-waha`
3. Restart n8n if needed

### Add Credentials

1. Go to Credentials → Add Credential
2. Search for "WAHA"
3. Configure:
   - Host URL: `http://waha:3000`
   - Session: `default`

### Example: Send Message Node

```
Node: WAHA
Action: Send a text message
Session: default
Chat ID: {{ $json.phone }}@c.us
Text: Hello {{ $json.name }}!
```

### Example: Receive Messages (Trigger)

```
Node: WAHA Trigger
Events: message
Session: default
```

This triggers workflow whenever you receive a WhatsApp message.

## API Reference

### Send Text
```bash
POST /api/sendText
{
  "session": "default",
  "chatId": "385911234567@c.us",
  "text": "Hello!"
}
```

### Send Image
```bash
POST /api/sendImage
{
  "session": "default",
  "chatId": "385911234567@c.us",
  "file": {
    "url": "https://example.com/image.jpg"
  },
  "caption": "Check this out!"
}
```

### Send Document
```bash
POST /api/sendFile
{
  "session": "default", 
  "chatId": "385911234567@c.us",
  "file": {
    "url": "https://example.com/document.pdf"
  },
  "caption": "Here's the document"
}
```

### Check Session Status
```bash
GET /api/sessions/default
```

### Get QR Code
```bash
GET /api/sessions/default/auth/qr
```

## Phone Number Format

Always use format: `[country][number]@c.us`

| Country | Example |
|---------|---------|
| Croatia (+385) | `385911234567@c.us` |
| Germany (+49) | `491701234567@c.us` |
| USA (+1) | `12025551234@c.us` |

**No + prefix. No spaces. No dashes.**

## Webhooks (Incoming Messages)

WAHA sends incoming messages to n8n via webhook.

Configured in docker-compose.yml:
```
WHATSAPP_HOOK_URL=http://n8n:5678/webhook/whatsapp
WHATSAPP_HOOK_EVENTS=message,session.status
```

Create a Webhook node in n8n at path `/webhook/whatsapp` to receive messages.

## Best Practices

### Avoid Getting Banned

1. **Start slow**: 5-10 messages/day for first week
2. **Gradual increase**: Add 10 messages/day each week
3. **Don't spam**: Personalize messages, avoid bulk identical texts
4. **Respect replies**: If someone says "stop", stop messaging them
5. **Business hours**: Send during normal hours (9-18)
6. **Warm the number**: Use the number normally for a few days before automation

### Message Templates

Good:
```
Pozdrav {{name}}! 

Vidio sam {{property}} na Booking.com - odlične recenzije!
Napravio sam besplatni demo web stranice: {{demo_url}}

Javite se ako vas zanima.
```

Bad:
```
BUY NOW! BEST WEBSITE! CLICK HERE! www.spam.com
```

### Rate Limits

| Tier | Messages/Day | When |
|------|--------------|------|
| New number | 5-10 | First week |
| Warmed up | 50-100 | After 2-4 weeks |
| Established | 200+ | After 1-2 months |

## Troubleshooting

### QR Code Not Showing

```bash
# Check WAHA logs
docker compose logs waha

# Restart WAHA
docker compose restart waha
```

### Session Disconnected

1. Open dashboard: http://localhost:3000/dashboard
2. Delete old session
3. Start new session
4. Re-scan QR code

### Messages Not Sending

1. Check session status: `GET /api/sessions/default`
2. Verify phone number format (no +, ends with @c.us)
3. Check if number exists on WhatsApp
4. Look at WAHA logs for errors

### Phone Battery Drain

WhatsApp Web (and WAHA) keeps connection to your phone. This may drain battery faster. Consider:
- Keeping phone plugged in
- Using a dedicated old phone

## Security

### Protect Your API

In production, set API key in `.env`:
```
WAHA_API_KEY=your-secure-key
```

Then add to all requests:
```bash
curl -H "X-Api-Key: your-secure-key" ...
```

### Don't Expose Publicly

WAHA should NOT be accessible from internet without authentication.
The current setup only exposes it to internal Docker network + localhost.

## WAHA Plus vs Core

| Feature | Core (Free) | Plus ($19/mo) |
|---------|-------------|---------------|
| Sessions | 1 | Unlimited |
| Send messages | ✅ | ✅ |
| Receive messages | ✅ | ✅ |
| Webhooks | Basic | Advanced |
| Support | Community | Priority |

For single-number outreach, **Core is enough**.

## Links

- Documentation: https://waha.devlike.pro/
- GitHub: https://github.com/devlikeapro/waha
- n8n Workflows: https://waha-n8n-workflows.devlike.pro/
