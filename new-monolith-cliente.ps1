<#
.SYNOPSIS
  Generador de monolito MVC (.NET 10) + EF Core + PostgreSQL + Docker + FluentValidation, con SOLID.
  El proyecto generado corre igual en Docker y en Visual Studio (F5).

.EXAMPLE
  .\este-script.ps1 -Name MiApp -OutputPath C:\Development\Projects
  .\este-script.ps1 -Name MiApp -OutputPath C:\Development\Projects -Run
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$OutputPath = (Get-Location).Path,
    [int]$DbPort = 5433,
    [int]$AppPort = 8080,
    [switch]$SkipMigration,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
    throw "Name debe ser un identificador valido de C# (letras, numeros, _ ; sin espacios ni guiones)."
}

$Lower = $Name.ToLower()
$Root  = Join-Path $OutputPath $Name
$Proj  = Join-Path $Root "src\$Name"

if (Test-Path $Root) { throw "Ya existe $Root" }

# Tokens propios de cada plantilla (los define la seccion "Plantilla" de mas abajo)
$Extras = @{}

function Write-File([string]$RelPath, [string]$Content) {
    $full = Join-Path $Root $RelPath
    $dir  = Split-Path $full -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $text = $Content
    foreach ($k in $Extras.Keys) { $text = $text.Replace($k, [string]$Extras[$k]) }
    $text = $text.Replace('__NAME__', $Name).Replace('__LOWER__', $Lower).Replace('__DBPORT__', "$DbPort").Replace('__APPPORT__', "$AppPort")
    [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- Plantilla: CLIENTE (CRUD comun, una tabla, 10 campos)
$TemplateName = 'Cliente'
$HasEntities  = $true

$Extras['__TEMPLATE__']    = 'Cliente común (CRUD simple, una sola tabla, 10 campos, sin portada)'
$Extras['__CONTROLLER__']  = 'Clientes'
$Extras['__NAV__']         = ''
$Extras['__DB_USINGS__']   = 'using __NAME__.Domain.Entities;'
$Extras['__DBSETS__']      = '    public DbSet<Cliente> Clientes => Set<Cliente>();'
$Extras['__INFRA_EXTRA__'] = '        services.AddScoped<IClienteRepository, ClienteRepository>();'
$Extras['__APP_USINGS__']  = 'using __NAME__.Application.Services;'
$Extras['__APP_EXTRA__']   = '        services.AddScoped<IClienteService, ClienteService>();'

# ---------------------------------------------------------------- scaffold
Write-Host ">> Plantilla: $TemplateName" -ForegroundColor Cyan
Write-Host ">> Creando solucion y proyecto..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $Root -Force | Out-Null
Push-Location $Root
try {
    dotnet new sln -n $Name --format sln | Out-Null
    dotnet new mvc -n $Name -o "src/$Name" --no-https | Out-Null
    dotnet sln "$Name.sln" add "src/$Name/$Name.csproj" | Out-Null

    Write-Host ">> Instalando paquetes NuGet..." -ForegroundColor Cyan
    # Versiones fijas a la serie 10 / 12: la ultima de nuget puede apuntar a net11 y no sirve para net10.0.
    $packages = @(
        @{ Id = 'Microsoft.EntityFrameworkCore';                       Version = '10.0.0' },
        @{ Id = 'Microsoft.EntityFrameworkCore.Design';                Version = '10.0.0' },
        @{ Id = 'Npgsql.EntityFrameworkCore.PostgreSQL';               Version = '10.0.0' },
        @{ Id = 'FluentValidation';                                    Version = '12.0.0' },
        @{ Id = 'FluentValidation.DependencyInjectionExtensions';      Version = '12.0.0' },
        @{ Id = 'DotNetEnv';                                           Version = $null }
    )
    Push-Location "src/$Name"
    foreach ($pkg in $packages) {
        if ($pkg.Version) { dotnet add package $pkg.Id --version $pkg.Version }
        else              { dotnet add package $pkg.Id }
        if ($LASTEXITCODE -ne 0) { throw "Fallo al instalar el paquete $($pkg.Id) (ver error arriba)" }
    }
    Pop-Location

    $csprojText = Get-Content (Join-Path $Proj "$Name.csproj") -Raw
    if ($csprojText -notmatch 'Microsoft\.EntityFrameworkCore\.Design') { throw "Microsoft.EntityFrameworkCore.Design no quedo en el csproj" }
}
finally { Pop-Location }

# Limpieza de lo que trae la plantilla y no usamos
Remove-Item (Join-Path $Proj 'Controllers\HomeController.cs') -Force
Remove-Item (Join-Path $Proj 'Views\Home') -Recurse -Force
Remove-Item (Join-Path $Proj 'Models') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Proj 'Views\Shared\Error.cshtml') -Force -ErrorAction SilentlyContinue

Write-File "src\$Name\Views\_ViewImports.cshtml" @'
@using __NAME__
@addTagHelper *, Microsoft.AspNetCore.Mvc.TagHelpers
'@

# ---------------------------------------------------------------- Domain (base)
Write-File "src\$Name\Domain\Common\BaseEntity.cs" @'
namespace __NAME__.Domain.Common;

public abstract class BaseEntity
{
    public int Id { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
'@

# ---------------------------------------------------------------- Application (base)
Write-File "src\$Name\Application\Abstractions\IRepository.cs" @'
using __NAME__.Domain.Common;

namespace __NAME__.Application.Abstractions;

// ISP: contrato pequeno y generico. DIP: la capa Application depende de esta abstraccion, no de EF.
public interface IRepository<T> where T : BaseEntity
{
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct = default);
    Task<T?> GetByIdAsync(int id, CancellationToken ct = default);
    Task AddAsync(T entity, CancellationToken ct = default);
    Task UpdateAsync(T entity, CancellationToken ct = default);
    Task DeleteAsync(T entity, CancellationToken ct = default);
}
'@

Write-File "src\$Name\Application\DependencyInjection.cs" @'
using FluentValidation;
using __NAME__.Application.Abstractions;
__APP_USINGS__

namespace __NAME__.Application;

public static class DependencyInjection
{
    // OCP: para agregar un modulo nuevo se registra aqui, sin tocar Program.cs ni lo existente.
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        // Registra automaticamente todos los AbstractValidator<T> del proyecto.
        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);
__APP_EXTRA__
        return services;
    }
}
'@

# ---------------------------------------------------------------- Infrastructure (base)
Write-File "src\$Name\Infrastructure\Persistence\AppDbContext.cs" @'
using Microsoft.EntityFrameworkCore;
__DB_USINGS__

namespace __NAME__.Infrastructure.Persistence;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

__DBSETS__

    protected override void OnModelCreating(ModelBuilder modelBuilder)
        => modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
}
'@

Write-File "src\$Name\Infrastructure\Persistence\Repository.cs" @'
using Microsoft.EntityFrameworkCore;
using __NAME__.Application.Abstractions;
using __NAME__.Domain.Common;

namespace __NAME__.Infrastructure.Persistence;

// LSP: cualquier Repository<T> puede sustituir a IRepository<T>.
public class Repository<T> : IRepository<T> where T : BaseEntity
{
    protected readonly AppDbContext Db;
    public Repository(AppDbContext db) => Db = db;

    public async Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct = default)
        => await Db.Set<T>().AsNoTracking().OrderBy(x => x.Id).ToListAsync(ct);

    public Task<T?> GetByIdAsync(int id, CancellationToken ct = default)
        => Db.Set<T>().FirstOrDefaultAsync(x => x.Id == id, ct);

    public async Task AddAsync(T entity, CancellationToken ct = default)
    {
        await Db.Set<T>().AddAsync(entity, ct);
        await Db.SaveChangesAsync(ct);
    }

    public async Task UpdateAsync(T entity, CancellationToken ct = default)
    {
        Db.Set<T>().Update(entity);
        await Db.SaveChangesAsync(ct);
    }

    public async Task DeleteAsync(T entity, CancellationToken ct = default)
    {
        Db.Set<T>().Remove(entity);
        await Db.SaveChangesAsync(ct);
    }
}
'@

Write-File "src\$Name\Infrastructure\DependencyInjection.cs" @'
using Microsoft.EntityFrameworkCore;
using Npgsql;
using __NAME__.Application.Abstractions;
using __NAME__.Infrastructure.Persistence;

namespace __NAME__.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        var connectionString = BuildConnectionString(config);

        services.AddDbContext<AppDbContext>(opt =>
            opt.UseNpgsql(connectionString, npgsql =>
                npgsql.MigrationsAssembly(typeof(AppDbContext).Assembly.FullName)));

        services.AddScoped(typeof(IRepository<>), typeof(Repository<>));
__INFRA_EXTRA__
        return services;
    }

    // Misma logica en Docker y en Visual Studio: todo viene de variables de entorno (.env en VS, compose en Docker).
    private static string BuildConnectionString(IConfiguration config)
    {
        var full = config.GetConnectionString("Default");
        if (!string.IsNullOrWhiteSpace(full)) return full;

        return new NpgsqlConnectionStringBuilder
        {
            Host = config["DB_HOST"] ?? "localhost",
            Port = int.TryParse(config["DB_PORT"], out var p) ? p : 5432,
            Database = config["DB_NAME"] ?? throw new InvalidOperationException("Falta DB_NAME (ver sample.env)"),
            Username = config["DB_USER"] ?? throw new InvalidOperationException("Falta DB_USER (ver sample.env)"),
            Password = config["DB_PASSWORD"] ?? throw new InvalidOperationException("Falta DB_PASSWORD (ver sample.env)")
        }.ConnectionString;
    }

    public static async Task ApplyMigrationsAsync(this WebApplication app)
    {
        if (!string.Equals(app.Configuration["AUTO_MIGRATE"] ?? "true", "true", StringComparison.OrdinalIgnoreCase))
            return;

        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Reintentos: en Docker la BD puede tardar unos segundos en aceptar conexiones.
        for (var attempt = 1; ; attempt++)
        {
            try { await db.Database.MigrateAsync(); return; }
            catch (NpgsqlException) when (attempt < 10) { await Task.Delay(TimeSpan.FromSeconds(2)); }
        }
    }
}
'@

# ---------------------------------------------------------------- Web (base)
Write-File "src\$Name\Extensions\ValidationExtensions.cs" @'
using FluentValidation.Results;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace __NAME__.Extensions;

public static class ValidationExtensions
{
    // Pasa los errores de FluentValidation al ModelState para que las vistas los muestren con asp-validation-for.
    public static void AddToModelState(this ValidationResult result, ModelStateDictionary modelState)
    {
        foreach (var error in result.Errors)
            modelState.AddModelError(error.PropertyName, error.ErrorMessage);
    }
}
'@

Write-File "src\$Name\Program.cs" @'
using System.Globalization;
using FluentValidation;
using __NAME__.Application;
using __NAME__.Infrastructure;

// Carga .env (busca hacia arriba desde la carpeta actual). En Docker no existe y se usan las env del compose.
try { DotNetEnv.Env.NoClobber().TraversePath().Load(); } catch (FileNotFoundException) { }

// Mensajes por defecto de FluentValidation en español.
ValidatorOptions.Global.LanguageManager.Culture = new CultureInfo("es");

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews(options =>
{
    // La validacion la hace FluentValidation: evitamos el [Required] implicito de MVC para strings no nulos.
    options.SuppressImplicitRequiredAttributeForNonNullableReferenceTypes = true;
});
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

var app = builder.Build();

await app.ApplyMigrationsAsync();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler(e => e.Run(ctx => ctx.Response.WriteAsync("Error inesperado")));
}

app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=__CONTROLLER__}/{action=Index}/{id?}");

app.Run();
'@

Write-File "src\$Name\Views\Shared\_Layout.cshtml" @'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>@ViewData["Title"] - __NAME__</title>
    <link rel="stylesheet" href="~/lib/bootstrap/dist/css/bootstrap.min.css" />
</head>
<body>
    <nav class="navbar navbar-dark bg-dark mb-4">
        <div class="container">
            <a class="navbar-brand" asp-controller="__CONTROLLER__" asp-action="Index">__NAME__</a>
            __NAV__
        </div>
    </nav>
    <main class="container pb-5">
        @RenderBody()
    </main>
    <script src="~/lib/jquery/dist/jquery.min.js"></script>
    <script src="~/lib/bootstrap/dist/js/bootstrap.bundle.min.js"></script>
    @await RenderSectionAsync("Scripts", required: false)
</body>
</html>
'@

# ---------------------------------------------------------------- Domain
Write-File "src\$Name\Domain\Entities\Cliente.cs" @'
using __NAME__.Domain.Common;

namespace __NAME__.Domain.Entities;

public class Cliente : BaseEntity
{
    public string Cedula { get; set; } = string.Empty;
    public string Nombres { get; set; } = string.Empty;
    public string Apellidos { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Telefono { get; set; } = string.Empty;
    public DateOnly FechaNacimiento { get; set; }
    public string? Direccion { get; set; }
    public string Ciudad { get; set; } = string.Empty;
    public bool Activo { get; set; } = true;
    public string? Observaciones { get; set; }
}
'@

# ---------------------------------------------------------------- Application
Write-File "src\$Name\Application\Dtos\ClienteDto.cs" @'
namespace __NAME__.Application.Dtos;

// DTO "tonto": solo transporta datos. Las reglas viven en Validators/ClienteValidator.cs (SRP).
public class ClienteDto
{
    public int Id { get; set; }
    public string Cedula { get; set; } = string.Empty;
    public string Nombres { get; set; } = string.Empty;
    public string Apellidos { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Telefono { get; set; } = string.Empty;
    public DateOnly FechaNacimiento { get; set; }
    public string? Direccion { get; set; }
    public string Ciudad { get; set; } = string.Empty;
    public bool Activo { get; set; } = true;
    public string? Observaciones { get; set; }
}
'@

Write-File "src\$Name\Application\Abstractions\IClienteRepository.cs" @'
using __NAME__.Domain.Entities;

namespace __NAME__.Application.Abstractions;

// ISP: lo especifico de Cliente va en su propia interfaz, sin engordar IRepository<T>.
public interface IClienteRepository : IRepository<Cliente>
{
    Task<bool> ExistsByCedulaAsync(string cedula, int excludeId, CancellationToken ct = default);
    Task<bool> ExistsByEmailAsync(string email, int excludeId, CancellationToken ct = default);
}
'@

Write-File "src\$Name\Application\Abstractions\IClienteService.cs" @'
using __NAME__.Application.Dtos;

namespace __NAME__.Application.Abstractions;

public interface IClienteService
{
    Task<IReadOnlyList<ClienteDto>> GetAllAsync(CancellationToken ct = default);
    Task<ClienteDto?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<ClienteDto> CreateAsync(ClienteDto dto, CancellationToken ct = default);
    Task<bool> UpdateAsync(int id, ClienteDto dto, CancellationToken ct = default);
    Task<bool> DeleteAsync(int id, CancellationToken ct = default);
}
'@

Write-File "src\$Name\Application\Validators\ClienteValidator.cs" @'
using FluentValidation;
using __NAME__.Application.Abstractions;
using __NAME__.Application.Dtos;

namespace __NAME__.Application.Validators;

// SRP: toda la validacion de Cliente vive aqui, ni en el DTO ni en el controlador.
public class ClienteValidator : AbstractValidator<ClienteDto>
{
    public ClienteValidator(IClienteRepository clientes)
    {
        RuleFor(x => x.Cedula).Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("La cédula es obligatoria")
            .Matches(@"^\d{10}$").WithMessage("La cédula debe tener exactamente 10 dígitos")
            .MustAsync(async (dto, cedula, ct) => !await clientes.ExistsByCedulaAsync(cedula, dto.Id, ct))
            .WithMessage("Ya existe un cliente con esa cédula");

        RuleFor(x => x.Nombres).Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("Los nombres son obligatorios")
            .MaximumLength(80).WithMessage("Máximo 80 caracteres");

        RuleFor(x => x.Apellidos).Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("Los apellidos son obligatorios")
            .MaximumLength(80).WithMessage("Máximo 80 caracteres");

        RuleFor(x => x.Email).Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("El correo es obligatorio")
            .MaximumLength(120).WithMessage("Máximo 120 caracteres")
            .EmailAddress().WithMessage("El correo no tiene un formato válido")
            .MustAsync(async (dto, email, ct) => !await clientes.ExistsByEmailAsync(email, dto.Id, ct))
            .WithMessage("Ya existe un cliente con ese correo");

        RuleFor(x => x.Telefono).Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("El teléfono es obligatorio")
            .Matches(@"^[0-9+\-\s]{7,15}$").WithMessage("El teléfono debe tener entre 7 y 15 caracteres (dígitos, +, -)");

        RuleFor(x => x.FechaNacimiento)
            .Must(f => f >= new DateOnly(1900, 1, 1) && f <= DateOnly.FromDateTime(DateTime.Today))
            .WithMessage("La fecha de nacimiento no es válida");

        RuleFor(x => x.Direccion)
            .MaximumLength(200).WithMessage("Máximo 200 caracteres");

        RuleFor(x => x.Ciudad).Cascade(CascadeMode.Stop)
            .NotEmpty().WithMessage("La ciudad es obligatoria")
            .MaximumLength(60).WithMessage("Máximo 60 caracteres");

        RuleFor(x => x.Observaciones)
            .MaximumLength(500).WithMessage("Máximo 500 caracteres");
    }
}
'@

Write-File "src\$Name\Application\Services\ClienteService.cs" @'
using __NAME__.Application.Abstractions;
using __NAME__.Application.Dtos;
using __NAME__.Domain.Entities;

namespace __NAME__.Application.Services;

// SRP: solo orquesta los casos de uso de Cliente. Depende de abstracciones (DIP).
public class ClienteService : IClienteService
{
    private readonly IClienteRepository _repo;

    public ClienteService(IClienteRepository repo) => _repo = repo;

    public async Task<IReadOnlyList<ClienteDto>> GetAllAsync(CancellationToken ct = default)
        => (await _repo.GetAllAsync(ct)).Select(ToDto).ToList();

    public async Task<ClienteDto?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        var entity = await _repo.GetByIdAsync(id, ct);
        return entity is null ? null : ToDto(entity);
    }

    public async Task<ClienteDto> CreateAsync(ClienteDto dto, CancellationToken ct = default)
    {
        var entity = new Cliente();
        Apply(entity, dto);
        await _repo.AddAsync(entity, ct);
        return ToDto(entity);
    }

    public async Task<bool> UpdateAsync(int id, ClienteDto dto, CancellationToken ct = default)
    {
        var entity = await _repo.GetByIdAsync(id, ct);
        if (entity is null) return false;
        Apply(entity, dto);
        await _repo.UpdateAsync(entity, ct);
        return true;
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken ct = default)
    {
        var entity = await _repo.GetByIdAsync(id, ct);
        if (entity is null) return false;
        await _repo.DeleteAsync(entity, ct);
        return true;
    }

    private static void Apply(Cliente e, ClienteDto d)
    {
        e.Cedula = d.Cedula.Trim();
        e.Nombres = d.Nombres.Trim();
        e.Apellidos = d.Apellidos.Trim();
        e.Email = d.Email.Trim().ToLowerInvariant();
        e.Telefono = d.Telefono.Trim();
        e.FechaNacimiento = d.FechaNacimiento;
        e.Direccion = string.IsNullOrWhiteSpace(d.Direccion) ? null : d.Direccion.Trim();
        e.Ciudad = d.Ciudad.Trim();
        e.Activo = d.Activo;
        e.Observaciones = string.IsNullOrWhiteSpace(d.Observaciones) ? null : d.Observaciones.Trim();
    }

    private static ClienteDto ToDto(Cliente c) => new()
    {
        Id = c.Id,
        Cedula = c.Cedula,
        Nombres = c.Nombres,
        Apellidos = c.Apellidos,
        Email = c.Email,
        Telefono = c.Telefono,
        FechaNacimiento = c.FechaNacimiento,
        Direccion = c.Direccion,
        Ciudad = c.Ciudad,
        Activo = c.Activo,
        Observaciones = c.Observaciones
    };
}
'@

# ---------------------------------------------------------------- Infrastructure
Write-File "src\$Name\Infrastructure\Persistence\ClienteRepository.cs" @'
using Microsoft.EntityFrameworkCore;
using __NAME__.Application.Abstractions;
using __NAME__.Domain.Entities;

namespace __NAME__.Infrastructure.Persistence;

public class ClienteRepository : Repository<Cliente>, IClienteRepository
{
    public ClienteRepository(AppDbContext db) : base(db) { }

    public Task<bool> ExistsByCedulaAsync(string cedula, int excludeId, CancellationToken ct = default)
    {
        var value = cedula.Trim();
        return Db.Set<Cliente>().AnyAsync(c => c.Cedula == value && c.Id != excludeId, ct);
    }

    public Task<bool> ExistsByEmailAsync(string email, int excludeId, CancellationToken ct = default)
    {
        var value = email.Trim().ToLowerInvariant();
        return Db.Set<Cliente>().AnyAsync(c => c.Email == value && c.Id != excludeId, ct);
    }
}
'@

Write-File "src\$Name\Infrastructure\Persistence\Configurations\ClienteConfiguration.cs" @'
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using __NAME__.Domain.Entities;

namespace __NAME__.Infrastructure.Persistence.Configurations;

public class ClienteConfiguration : IEntityTypeConfiguration<Cliente>
{
    public void Configure(EntityTypeBuilder<Cliente> b)
    {
        b.ToTable("clientes");
        b.HasKey(x => x.Id);

        b.Property(x => x.Cedula).IsRequired().HasMaxLength(10);
        b.Property(x => x.Nombres).IsRequired().HasMaxLength(80);
        b.Property(x => x.Apellidos).IsRequired().HasMaxLength(80);
        b.Property(x => x.Email).IsRequired().HasMaxLength(120);
        b.Property(x => x.Telefono).IsRequired().HasMaxLength(15);
        b.Property(x => x.Direccion).HasMaxLength(200);
        b.Property(x => x.Ciudad).IsRequired().HasMaxLength(60);
        b.Property(x => x.Observaciones).HasMaxLength(500);

        b.HasIndex(x => x.Cedula).IsUnique();
        b.HasIndex(x => x.Email).IsUnique();
    }
}
'@

# ---------------------------------------------------------------- Web: controlador
Write-File "src\$Name\Controllers\ClientesController.cs" @'
using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using __NAME__.Application.Abstractions;
using __NAME__.Application.Dtos;
using __NAME__.Extensions;

namespace __NAME__.Controllers;

// Controlador delgado: solo HTTP. La logica esta en IClienteService y las reglas en ClienteValidator.
public class ClientesController : Controller
{
    private readonly IClienteService _service;
    private readonly IValidator<ClienteDto> _validator;

    public ClientesController(IClienteService service, IValidator<ClienteDto> validator)
    {
        _service = service;
        _validator = validator;
    }

    public async Task<IActionResult> Index(CancellationToken ct)
        => View(await _service.GetAllAsync(ct));

    public IActionResult Create()
        => View(new ClienteDto { FechaNacimiento = DateOnly.FromDateTime(DateTime.Today.AddYears(-18)) });

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(ClienteDto dto, CancellationToken ct)
    {
        dto.Id = 0;
        (await _validator.ValidateAsync(dto, ct)).AddToModelState(ModelState);
        if (!ModelState.IsValid) return View(dto);

        await _service.CreateAsync(dto, ct);
        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> Edit(int id, CancellationToken ct)
    {
        var dto = await _service.GetByIdAsync(id, ct);
        return dto is null ? NotFound() : View(dto);
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(int id, ClienteDto dto, CancellationToken ct)
    {
        dto.Id = id;
        (await _validator.ValidateAsync(dto, ct)).AddToModelState(ModelState);
        if (!ModelState.IsValid) return View(dto);

        return await _service.UpdateAsync(id, dto, ct) ? RedirectToAction(nameof(Index)) : NotFound();
    }

    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var dto = await _service.GetByIdAsync(id, ct);
        return dto is null ? NotFound() : View(dto);
    }

    [HttpPost, ActionName("Delete"), ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteConfirmed(int id, CancellationToken ct)
    {
        await _service.DeleteAsync(id, ct);
        return RedirectToAction(nameof(Index));
    }
}
'@

# ---------------------------------------------------------------- Web: vistas
Write-File "src\$Name\Views\Clientes\Index.cshtml" @'
@model IEnumerable<__NAME__.Application.Dtos.ClienteDto>
@{ ViewData["Title"] = "Clientes"; }

<div class="d-flex justify-content-between align-items-center mb-3">
    <h2>Clientes</h2>
    <a class="btn btn-primary" asp-action="Create">Nuevo cliente</a>
</div>

<div class="table-responsive">
    <table class="table table-striped align-middle">
        <thead>
            <tr>
                <th>Cédula</th><th>Cliente</th><th>Correo</th><th>Teléfono</th>
                <th>Ciudad</th><th>Activo</th><th></th>
            </tr>
        </thead>
        <tbody>
        @foreach (var c in Model)
        {
            <tr>
                <td>@c.Cedula</td>
                <td>@c.Nombres @c.Apellidos</td>
                <td>@c.Email</td>
                <td>@c.Telefono</td>
                <td>@c.Ciudad</td>
                <td>@(c.Activo ? "Sí" : "No")</td>
                <td class="text-end text-nowrap">
                    <a class="btn btn-sm btn-outline-secondary" asp-action="Edit" asp-route-id="@c.Id">Editar</a>
                    <a class="btn btn-sm btn-outline-danger" asp-action="Delete" asp-route-id="@c.Id">Eliminar</a>
                </td>
            </tr>
        }
        </tbody>
    </table>
</div>
'@

Write-File "src\$Name\Views\Clientes\_Form.cshtml" @'
@model __NAME__.Application.Dtos.ClienteDto

<div asp-validation-summary="ModelOnly" class="text-danger"></div>

<div class="row g-3 mb-3">
    <div class="col-md-4">
        <label asp-for="Cedula" class="form-label">Cédula</label>
        <input asp-for="Cedula" class="form-control" maxlength="10" />
        <span asp-validation-for="Cedula" class="text-danger"></span>
    </div>
    <div class="col-md-4">
        <label asp-for="Nombres" class="form-label">Nombres</label>
        <input asp-for="Nombres" class="form-control" />
        <span asp-validation-for="Nombres" class="text-danger"></span>
    </div>
    <div class="col-md-4">
        <label asp-for="Apellidos" class="form-label">Apellidos</label>
        <input asp-for="Apellidos" class="form-control" />
        <span asp-validation-for="Apellidos" class="text-danger"></span>
    </div>

    <div class="col-md-6">
        <label asp-for="Email" class="form-label">Correo electrónico</label>
        <input asp-for="Email" class="form-control" />
        <span asp-validation-for="Email" class="text-danger"></span>
    </div>
    <div class="col-md-6">
        <label asp-for="Telefono" class="form-label">Teléfono</label>
        <input asp-for="Telefono" class="form-control" />
        <span asp-validation-for="Telefono" class="text-danger"></span>
    </div>

    <div class="col-md-4">
        <label asp-for="FechaNacimiento" class="form-label">Fecha de nacimiento</label>
        <input asp-for="FechaNacimiento" class="form-control" />
        <span asp-validation-for="FechaNacimiento" class="text-danger"></span>
    </div>
    <div class="col-md-4">
        <label asp-for="Ciudad" class="form-label">Ciudad</label>
        <input asp-for="Ciudad" class="form-control" />
        <span asp-validation-for="Ciudad" class="text-danger"></span>
    </div>
    <div class="col-md-4 d-flex align-items-end">
        <div class="form-check">
            <input asp-for="Activo" class="form-check-input" />
            <label asp-for="Activo" class="form-check-label">Activo</label>
        </div>
    </div>

    <div class="col-12">
        <label asp-for="Direccion" class="form-label">Dirección (opcional)</label>
        <input asp-for="Direccion" class="form-control" />
        <span asp-validation-for="Direccion" class="text-danger"></span>
    </div>
    <div class="col-12">
        <label asp-for="Observaciones" class="form-label">Observaciones (opcional)</label>
        <textarea asp-for="Observaciones" class="form-control" rows="3"></textarea>
        <span asp-validation-for="Observaciones" class="text-danger"></span>
    </div>
</div>
'@

Write-File "src\$Name\Views\Clientes\Create.cshtml" @'
@model __NAME__.Application.Dtos.ClienteDto
@{ ViewData["Title"] = "Nuevo cliente"; }

<h2>Nuevo cliente</h2>
<form asp-action="Create" method="post">
    <partial name="_Form" model="Model" />
    <button class="btn btn-primary" type="submit">Guardar</button>
    <a class="btn btn-link" asp-action="Index">Cancelar</a>
</form>
'@

Write-File "src\$Name\Views\Clientes\Edit.cshtml" @'
@model __NAME__.Application.Dtos.ClienteDto
@{ ViewData["Title"] = "Editar cliente"; }

<h2>Editar cliente</h2>
<form asp-action="Edit" asp-route-id="@Model.Id" method="post">
    <partial name="_Form" model="Model" />
    <button class="btn btn-primary" type="submit">Guardar</button>
    <a class="btn btn-link" asp-action="Index">Cancelar</a>
</form>
'@

Write-File "src\$Name\Views\Clientes\Delete.cshtml" @'
@model __NAME__.Application.Dtos.ClienteDto
@{ ViewData["Title"] = "Eliminar cliente"; }

<h2>Eliminar cliente</h2>
<p>¿Seguro que quieres eliminar a <strong>@Model.Nombres @Model.Apellidos</strong> (cédula @Model.Cedula)?</p>
<form asp-action="Delete" asp-route-id="@Model.Id" method="post">
    <button class="btn btn-danger" type="submit">Eliminar</button>
    <a class="btn btn-link" asp-action="Index">Cancelar</a>
</form>
'@

# ---------------------------------------------------------------- Docker + entorno
$dbPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ })

Write-File "sample.env" @'
# Copia este archivo a .env y ajusta los valores. .env NO se sube a git.
# En Visual Studio: DB_HOST=localhost y DB_PORT=el puerto publicado de la BD (compose la expone en DB_PORT).
# En Docker el compose sobreescribe DB_HOST=db y DB_PORT=5432 solo para el contenedor web.
DB_HOST=localhost
DB_PORT=__DBPORT__
DB_NAME=__LOWER__
DB_USER=postgres
DB_PASSWORD=cambia_esta_clave
APP_PORT=__APPPORT__
AUTO_MIGRATE=true
'@

Write-File ".env" @"
DB_HOST=localhost
DB_PORT=$DbPort
DB_NAME=$Lower
DB_USER=postgres
DB_PASSWORD=$dbPassword
APP_PORT=$AppPort
AUTO_MIGRATE=true
"@

Write-File "docker-compose.yml" @'
services:
  db:
    image: postgres:17-alpine
    container_name: __LOWER__-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "${DB_PORT}:5432"   # expuesta para que Visual Studio se conecte por localhost
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10

  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: __LOWER__-web
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ASPNETCORE_URLS: http://+:8080
      DB_HOST: db
      DB_PORT: "5432"
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      AUTO_MIGRATE: ${AUTO_MIGRATE:-true}
    ports:
      - "${APP_PORT}:8080"

volumes:
  pgdata:
'@

Write-File "Dockerfile" @'
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY src/__NAME__/__NAME__.csproj src/__NAME__/
RUN dotnet restore src/__NAME__/__NAME__.csproj
COPY src/ src/
RUN dotnet publish src/__NAME__/__NAME__.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "__NAME__.dll"]
'@

Write-File ".dockerignore" @'
**/bin/
**/obj/
**/.vs/
.git/
.env
*.md
'@

Write-File ".gitignore" @'
bin/
obj/
.vs/
*.user
.env
'@

Write-File "scripts\migrations.ps1" @'
<#
  Uso:  .\scripts\migrations.ps1 -Name AddAlgo
  Crea una migracion nueva en Infrastructure/Persistence/Migrations.
  Equivalente en Visual Studio (Package Manager Console, proyecto por defecto = __NAME__):
        Add-Migration AddAlgo -OutputDir Infrastructure/Persistence/Migrations
#>
param([Parameter(Mandatory = $true)][string]$Name)

$root = Split-Path $PSScriptRoot -Parent
$proj = Join-Path $root 'src\__NAME__\__NAME__.csproj'

dotnet ef migrations add $Name `
    --project $proj --startup-project $proj `
    --context AppDbContext `
    --output-dir Infrastructure/Persistence/Migrations
'@

Write-File "README.md" @'
# __NAME__

Plantilla: __TEMPLATE__

Monolito MVC (.NET 10) con EF Core + PostgreSQL + FluentValidation. Capas dentro de un solo proyecto: Domain, Application (abstracciones, servicios, validadores), Infrastructure y Web (Controllers/Views).

## Docker
    docker compose up -d --build
    http://localhost:__APPPORT__

## Visual Studio
1. Copia sample.env a .env en la raiz (el generador ya crea uno).
2. Levanta solo la BD:  docker compose up -d db   (o apunta el .env a tu PostgreSQL local)
3. Abre __NAME__.sln y presiona F5. Las migraciones se aplican solas al arrancar (AUTO_MIGRATE=true).

## Migraciones nuevas
    .\scripts\migrations.ps1 -Name NombreMigracion
'@

# ---------------------------------------------------------------- Migracion inicial
if ($HasEntities -and -not $SkipMigration) {
    Write-Host ">> Generando migracion inicial..." -ForegroundColor Cyan
    $efMajor = 0
    try {
        $efOut = (dotnet ef --version 2>$null | Select-Object -Last 1)
        if ($efOut -match '^(\d+)\.') { $efMajor = [int]$Matches[1] }
    } catch { }
    if ($efMajor -eq 0) {
        Write-Host "   Instalando dotnet-ef 10.0.0 (global)..." -ForegroundColor Yellow
        dotnet tool install --global dotnet-ef --version 10.0.0
    }
    elseif ($efMajor -ne 10) {
        Write-Host "   Ajustando dotnet-ef a 10.0.0 (tenias la version $efMajor)..." -ForegroundColor Yellow
        dotnet tool update --global dotnet-ef --version 10.0.0
    }
    $csproj = Join-Path $Proj "$Name.csproj"
    dotnet ef migrations add InitialCreate `
        --project $csproj --startup-project $csproj `
        --context AppDbContext `
        --output-dir Infrastructure/Persistence/Migrations
    if ($LASTEXITCODE -ne 0) { throw "Fallo la migracion inicial (ver error arriba)" }
}
elseif (-not $HasEntities) {
    Write-Host ">> Plantilla vacia: sin migracion inicial. Cuando agregues tu primera entidad ejecuta .\scripts\migrations.ps1 -Name Inicial" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- Verificacion de build
Write-Host ">> Compilando..." -ForegroundColor Cyan
dotnet build (Join-Path $Root "$Name.sln") -c Release --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "El build fallo" }

Write-Host ""
Write-Host "Listo: $Root" -ForegroundColor Green
Write-Host "  Docker : cd $Root ; docker compose up -d --build   ->  http://localhost:$AppPort"
Write-Host "  VS     : docker compose up -d db  y abrir $Name.sln (F5)"

if ($Run) {
    Push-Location $Root
    docker compose up -d --build
    Pop-Location
}
