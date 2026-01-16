using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Hello from C#!");
app.MapGet("/health", () => "ok");

app.Run("http://0.0.0.0:8080");