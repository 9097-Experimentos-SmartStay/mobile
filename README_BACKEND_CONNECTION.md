# SmartStay Flutter - Backend Connection

La app consume el backend en:

```text
https://application-mobile-backend.onrender.com/api/v1
```

## Backend latest revisado

Endpoints vigentes detectados:

- POST `/authentication/sign-in`
- POST `/authentication/sign-up`
- GET/POST/PUT/DELETE `/users`
- POST `/users/{id}/assign-role`
- POST `/users/{id}/activate`
- POST `/users/change-password`
- GET/POST `/profiles`
- GET `/hotels`
- GET `/rooms`
- GET `/room-types`
- GET/POST `/bookings`
- GET/POST `/payments`
- GET `/analytics/performance/monthly`
- POST `/api/v1/io-t-emulator/rooms/{roomId}/inject-telemetry`
-- POST `/api/v1/io-t-emulator/rooms/{roomId}/thermostat`
- GET `/api/v1/io-t-emulator/rooms/{roomId}/actuators-state`



## Cambio importante detectado

El endpoint para asignar rol espera este body:

```json
{
  "targetUserId": 1,
  "newRole": "admin"
}
```

La app ya fue ajustada para enviar ambos campos.

## CORS

El backend actual permite solo este origen:

```text
https://smartstay-3cffc.web.app
```

Por eso Flutter Web en `localhost` puede fallar por CORS. Para probar localmente en Chrome se puede usar:

```bash
flutter run -d chrome --web-browser-flag="--disable-web-security" --web-browser-flag="--user-data-dir=C:\temp\flutter_chrome"
```

O pedir al backend que agregue:

```csharp
.WithOrigins(
    "https://smartstay-3cffc.web.app",
    "http://localhost:3000",
    "http://localhost:5000",
    "http://localhost:5173",
    "http://localhost:8080",
    "http://localhost:PORT_DEL_FLUTTER"
)
```
