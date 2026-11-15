using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using MiTienda.Application.Abstractions;
using MiTienda.Application.Dtos;
using MiTienda.Extensions;

namespace MiTienda.Controllers;

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