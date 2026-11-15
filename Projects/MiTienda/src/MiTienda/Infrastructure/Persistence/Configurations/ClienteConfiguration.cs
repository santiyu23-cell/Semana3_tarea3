using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using MiTienda.Domain.Entities;

namespace MiTienda.Infrastructure.Persistence.Configurations;

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