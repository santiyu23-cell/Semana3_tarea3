using FluentValidation;
using MiTienda.Application.Abstractions;
using MiTienda.Application.Dtos;

namespace MiTienda.Application.Validators;

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