# MiTienda

Plantilla: Cliente común (CRUD simple, una sola tabla, 10 campos, sin portada)

Monolito MVC (.NET 10) con EF Core + PostgreSQL + FluentValidation. Capas dentro de un solo proyecto: Domain, Application (abstracciones, servicios, validadores), Infrastructure y Web (Controllers/Views).

## Docker
    docker compose up -d --build
    http://localhost:8080

## Visual Studio
1. Copia sample.env a .env en la raiz (el generador ya crea uno).
2. Levanta solo la BD:  docker compose up -d db   (o apunta el .env a tu PostgreSQL local)
3. Abre MiTienda.sln y presiona F5. Las migraciones se aplican solas al arrancar (AUTO_MIGRATE=true).

## Migraciones nuevas
    .\scripts\migrations.ps1 -Name NombreMigracion