# SmartStay Flutter - Cliente

Aplicación Flutter enfocada en cliente/huésped.

## Enlaces

- **API (producción):** https://smartstay-movildev-api.onrender.com/api/v1 · documentación en [https://smartstay-movildev-api.onrender.com/scalar](https://smartstay-movildev-api.onrender.com/scalar)
- **Frontend web:** https://smartstay-movildev-web.vercel.app
- **Landing page:** https://smartstay-movildev-landing.vercel.app
- **Repositorios:** [backend](https://github.com/9097-Experimentos-SmartStay/backend) · [frontend](https://github.com/9097-Experimentos-SmartStay/frontend) · [landing-page](https://github.com/9097-Experimentos-SmartStay/landing-page) · [mobile](https://github.com/9097-Experimentos-SmartStay/mobile) · [Report](https://github.com/9097-Experimentos-SmartStay/Report)

## Flujo principal

- La app permite explorar hoteles y habitaciones sin iniciar sesión.
- Si el backend permite lectura pública, Flutter consume `/hotels` y `/rooms` directamente sin token.
- Si el backend todavía protege esos endpoints, Flutter muestra datos de vista previa para que la app no quede bloqueada.
- Para reservar, pagar, ver mis reservas, perfil y seguridad, se solicita iniciar sesión.

## Backend

URL del backend de producción:

```text
https://smartstay-movildev-api.onrender.com/api/v1
```

La URL se lee de `API_BASE_URL` (`lib/core/api_client.dart`). Para apuntar a producción de forma explícita:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=https://smartstay-movildev-api.onrender.com/api/v1
```

Cuando se actualice el backend, se recomienda dejar públicos:

```text
GET /api/v1/hotels
GET /api/v1/rooms
```

Y mantener protegidos:

```text
POST /api/v1/bookings
GET /api/v1/bookings/me
POST /api/v1/payments
POST /api/v1/users/change-password
POST /api/v1/profiles
```

## Ejecutar

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```
