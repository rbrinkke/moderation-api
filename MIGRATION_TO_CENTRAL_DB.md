# Migratie naar Centrale Database

**Datum:** 2025-11-13
**Status:** ✅ Compleet

## Wijzigingen

### 1. Docker Compose Configuratie

**Voor:**
- Eigen PostgreSQL container (postgres:15-alpine)
- Eigen Redis container
- Eigen netwerk (app-network)
- Port 8000

**Na:**
- ✅ Gebruikt centrale `activity-postgres-db` container
- ✅ Gebruikt gedeelde `auth-redis` container
- ✅ Gebruikt `activity-network` netwerk
- ✅ Port 8002 (om conflicten te voorkomen)

### 2. Database Configuratie

**Database URL:**
```
postgresql://postgres:postgres_secure_password_change_in_prod@activity-postgres-db:5432/activitydb
```

**Belangrijke punten:**
- Host: `activity-postgres-db` (centrale database container)
- Database: `activitydb` (met alle 40 tabellen)
- Schema: `activity` (automatisch via migraties)
- User: `postgres`
- Password: `postgres_secure_password_change_in_prod`

### 3. Redis Configuratie

**Redis URL:**
```
redis://auth-redis:6379/0
```

Gebruikt dezelfde Redis instance als auth-api voor:
- Rate limiting
- Caching
- Session management

### 4. Netwerk Configuratie

Gebruikt `activity-network` external network:
- Alle activity services in zelfde netwerk
- Direct communicatie tussen services
- Geen port mapping conflicts

### 5. Container Naam

Container naam: `moderation-api`
- Makkelijk te identificeren
- Consistent met andere services
- Gebruikt in logs en monitoring

## Database Schema

De moderation-api gebruikt tabellen uit het centrale schema:

**Moderation Tabellen:**
- `reports` (15 kolommen) - Abuse reports
- `user_badges` (11 kolommen) - Gamification badges
- `media_assets` (15 kolommen) - Media moderation

**User Tabellen:**
- `users` (34 kolommen) - User info voor moderation
- `user_blocks` (5 kolommen) - User blocking
- `user_settings` (14 kolommen) - User preferences

**Content Tabellen:**
- `posts` (17 kolommen) - Post moderation
- `comments` (10 kolommen) - Comment moderation
- `activities` (24 kolommen) - Activity moderation
- `communities` (17 kolommen) - Community moderation

## Deployment

### Starten

```bash
cd /mnt/d/activity/moderation-api
docker compose build
docker compose up -d
```

### Logs Checken

```bash
docker compose logs -f moderation-api
```

### Health Check

```bash
curl http://localhost:8002/health
```

### Stoppen

```bash
docker compose down
```

## Belangrijke Opmerkingen

1. **Geen eigen database meer** - Alle data in centrale database
2. **Gedeelde Redis** - Rate limiting gedeeld met auth-api
3. **Schema migraties** - Gebruik migrations/ folder voor schema wijzigingen
4. **Port 8002** - Om conflict met auth-api (8000) te voorkomen
5. **External network** - Moet `activity-network` netwerk bestaan

## Verificatie

Checklist na deployment:
- [ ] Container start zonder errors
- [ ] Database connectie succesvol
- [ ] Redis connectie succesvol
- [ ] Health endpoint reageert
- [ ] Auth-API communicatie werkt
- [ ] Moderation endpoints werken

## Rollback

Als er problemen zijn:
```bash
cd /mnt/d/activity/moderation-api
docker compose down
# Fix issues
docker compose up -d
```

---

**Status:** ✅ Klaar voor gebruik met centrale database
