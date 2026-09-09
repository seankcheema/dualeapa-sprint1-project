Initialize production-ready auth service with complete JWT authentication flow.

Features:
- User registration & login with bcrypt password hashing
- JWT token generation (1h access, 7d refresh)
- Email/password authentication via Passport Local strategy
- JWT Bearer token validation via Passport JWT strategy
- Route protection with AuthGuards
- 5 REST endpoints: register, login, refresh, verify, logout
- PostgreSQL User entity with TypeORM
- Full error handling and input validation

Stack:
- NestJS 12, TypeScript 5, ESM modules
- Passport.js (JWT + Local strategies)
- PostgreSQL + TypeORM
- Vitest for testing

File structure:
- src/auth/ (controller, service, strategies, guards, DTOs)
- src/users/ (entity, service, DTOs)
- src/config/ (database configuration)

Configuration:
- .env for database & JWT secrets
- Automatic schema sync in development mode

Ready to start:
npm run start:dev  # Runs on localhost:3001