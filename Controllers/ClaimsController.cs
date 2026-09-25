using ClaimsQueueManager.DTOs;
using ClaimsQueueManager.Services;
using Microsoft.AspNetCore.Mvc;

namespace ClaimsQueueManager.Controllers;

[ApiController]
[Route("api/claims")]
public class ClaimsController : ControllerBase
{
    private readonly IClaimsQueueService _service;
    public ClaimsController(IClaimsQueueService service) => _service = service;
    private string UserId => Request.Headers.TryGetValue("X-User-Id", out var v) && !string.IsNullOrWhiteSpace(v) ? v.ToString() : throw new BadHttpRequestException("X-User-Id header is required.");

    [HttpGet("queue/{queueCode}")]
    public async Task<IActionResult> List(string queueCode, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default) => Ok(await _service.ListAsync(queueCode, page, pageSize, ct));
    [HttpGet("next/{queueCode}")]
    public async Task<IActionResult> Next(string queueCode, CancellationToken ct) => Ok(await _service.GetNextAsync(queueCode, UserId, ct));
    [HttpPost("{taskId:int}/review")]
    public async Task<IActionResult> Review(int taskId, CancellationToken ct) { try { return Ok(await _service.ReviewAsync(taskId, UserId, ct)); } catch (LockConflictException e) { return Conflict(new { message = e.Message, code = "TASK_LOCKED" }); } }
    [HttpPost("{taskId:int}/release")]
    public async Task<IActionResult> Release(
    int taskId,
    CancellationToken ct)
    {
        try
        {
            await _service.ReleaseAsync(
                taskId,
                UserId,
                ct);

            return NoContent();
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new
            {
                message = ex.Message
            });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new
            {
                message = ex.Message
            });
        }
    }
    [HttpPost("{taskId:int}/forward")]
    public async Task<IActionResult> Forward(
        int taskId,
        ForwardRequest request,
        CancellationToken ct)
    {
        try
        {
            await _service.ForwardAsync(
                taskId,
                UserId,
                request.Username,
                ct);

            return NoContent();
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new
            {
                message = ex.Message
            });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new
            {
                message = ex.Message
            });
        }
    }
    [HttpPost("{taskId:int}/complete")]
    public async Task<IActionResult> Complete(
    int taskId,
    CompleteRequest request,
    CancellationToken ct)
    {
        try
        {
            await _service.CompleteAsync(
                taskId,
                UserId,
                request,
                ct);

            return NoContent();
        }
        catch (KeyNotFoundException ex)
        {
            return NotFound(new
            {
                message = ex.Message
            });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new
            {
                message = ex.Message
            });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new
            {
                message = ex.Message
            });
        }
    }
}
