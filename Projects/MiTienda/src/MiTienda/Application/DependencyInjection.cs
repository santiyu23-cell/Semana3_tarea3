using FluentValidation;
using MiTienda.Application.Abstractions;
using MiTienda.Application.Services;

namespace MiTienda.Application;

public static class DependencyInjection
{
    // OCP: para agregar un modulo nuevo se registra aqui, sin tocar Program.cs ni lo existente.
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        // Registra automaticamente todos los AbstractValidator<T> del proyecto.
        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);
        services.AddScoped<IClienteService, ClienteService>();
        return services;
    }
}