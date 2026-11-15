namespace MiTienda.Application.Dtos;

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