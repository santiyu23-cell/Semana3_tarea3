using MiTienda.Application.Abstractions;
using MiTienda.Application.Dtos;
using MiTienda.Domain.Entities;

namespace MiTienda.Application.Services;

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