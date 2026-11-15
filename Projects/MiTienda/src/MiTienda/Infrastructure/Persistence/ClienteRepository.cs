using Microsoft.EntityFrameworkCore;
using MiTienda.Application.Abstractions;
using MiTienda.Domain.Entities;

namespace MiTienda.Infrastructure.Persistence;

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