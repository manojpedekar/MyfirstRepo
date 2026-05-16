using Microsoft.AspNetCore.DataProtection.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using CLAWS.Data.Entities;

namespace CLAWS.Data.Context;

/// <summary>
/// Database context for the CLAWS application.
/// </summary>
public class ApplicationDbContext : DbContext, IDataProtectionKeyContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    /// <summary>
    /// Upload records.
    /// </summary>
    public DbSet<Upload> Uploads => Set<Upload>();

    /// <summary>
    /// API keys.
    /// </summary>
    public DbSet<ApiKey> ApiKeys => Set<ApiKey>();

    /// <summary>
    /// Configuration settings.
    /// </summary>
    public DbSet<ConfigurationEntry> Configuration => Set<ConfigurationEntry>();

    /// <summary>
    /// Import statistics.
    /// </summary>
    public DbSet<ImportStatistic> ImportStatistics => Set<ImportStatistic>();

    /// <summary>
    /// Log entries.
    /// </summary>
    public DbSet<LogEntry> Logs => Set<LogEntry>();

    /// <summary>
    /// Banner messages.
    /// </summary>
    public DbSet<BannerMessage> BannerMessages => Set<BannerMessage>();

    /// <summary>
    /// Data protection keys.
    /// </summary>
    public DbSet<DataProtectionKey> DataProtectionKeys => Set<DataProtectionKey>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Ensure app schema exists
        modelBuilder.HasDefaultSchema("app");

        // Upload entity configuration
        modelBuilder.Entity<Upload>(entity =>
        {
            entity.HasKey(e => e.UploadId);
            entity.HasIndex(e => e.Status);
            entity.HasIndex(e => e.UploadedBy);
            entity.HasIndex(e => e.UploadedAt).IsDescending();

            entity.Property(e => e.UploadId)
                .HasDefaultValueSql("NEWID()");

            entity.Property(e => e.UploadedAt)
                .HasDefaultValueSql("SYSUTCDATETIME()");
        });

        // ApiKey entity configuration
        modelBuilder.Entity<ApiKey>(entity =>
        {
            entity.HasKey(e => e.ApiKeyId);
            entity.HasIndex(e => e.KeyPrefix);

            entity.Property(e => e.ApiKeyId)
                .HasDefaultValueSql("NEWID()");

            entity.Property(e => e.CreatedAt)
                .HasDefaultValueSql("SYSUTCDATETIME()");
        });

        // Configuration entity configuration
        modelBuilder.Entity<ConfigurationEntry>(entity =>
        {
            entity.HasKey(e => e.ConfigKey);

            entity.Property(e => e.LastModifiedAt)
                .HasDefaultValueSql("SYSUTCDATETIME()");
        });

        // ImportStatistic entity configuration
        modelBuilder.Entity<ImportStatistic>(entity =>
        {
            entity.HasKey(e => e.StatId);

            entity.HasOne(e => e.Upload)
                .WithMany(u => u.ImportStatistics)
                .HasForeignKey(e => e.UploadId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        // Log entity configuration
        modelBuilder.Entity<LogEntry>(entity =>
        {
            entity.HasKey(e => e.LogId);
            entity.HasIndex(e => e.Timestamp).IsDescending();
            entity.HasIndex(e => e.CorrelationId);
            entity.HasIndex(e => e.UploadId);
            entity.HasIndex(e => e.Severity);
            entity.HasIndex(e => e.Category);

            entity.Property(e => e.Timestamp)
                .HasDefaultValueSql("SYSUTCDATETIME()")
                .HasPrecision(3);
        });

        // BannerMessage entity configuration
        modelBuilder.Entity<BannerMessage>(entity =>
        {
            entity.HasKey(e => e.BannerMessageId);
            entity.HasIndex(e => e.IsEnabled);
            entity.HasIndex(e => e.DisplayOrder);

            entity.Property(e => e.BannerMessageId)
                .HasDefaultValueSql("NEWID()");

            entity.Property(e => e.CreatedAt)
                .HasDefaultValueSql("SYSUTCDATETIME()");

            entity.Property(e => e.LastModifiedAt)
                .HasDefaultValueSql("SYSUTCDATETIME()");
        });
    }
}
