// ─────────────────────────────────────────────────────────────────────────────
// PRODUCTION startup
//
// Requires Microsoft.AspNetCore.App runtime and the AspNetCore package:
//   <PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.Http.AspNetCore" />
//
// using Microsoft.Azure.Functions.Worker.Builder;
//
// var builder = FunctionsApplication.CreateBuilder(args);
// builder.ConfigureFunctionsWebApplication();
// builder.Services
//     .AddApplicationInsightsTelemetryWorkerService()
//     .ConfigureFunctionsApplicationInsights()
//     .AddSingleton<IFileShareService, FileShareService>()
//     .AddHttpClient<IFacetsService, FacetsService>();
// builder.Build().Run();
//
// ─────────────────────────────────────────────────────────────────────────────
// LOCAL DEV startup
//
// Uses HostBuilder so only Microsoft.NETCore.App runtime is required.
// Functionally identical for HTTP-triggered functions.
// ─────────────────────────────────────────────────────────────────────────────

using ClaimAttachmentsApi.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services
            .AddApplicationInsightsTelemetryWorkerService()
            .AddSingleton<IFileShareService, FileShareService>()
            .AddHttpClient<IFacetsService, FacetsService>();
    })
    .Build();

await host.RunAsync();
