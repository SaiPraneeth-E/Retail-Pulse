# RetailPulse cleanup commands (Windows PowerShell)

# Stop and remove containers (keeps named volumes so PostgreSQL data is preserved)
docker compose down

# Full cleanup including named volume (DELETES PostgreSQL data - use with care)
# docker compose down -v

# Remove only Airflow logs (safe, does not touch PostgreSQL data)
# Remove-Item -Recurse -Force airflow\logs\* 2>$null

# Rebuild images without cache
# docker compose build --no-cache

# View running containers
# docker compose ps

# View logs
# docker compose logs -f postgres
# docker compose logs -f airflow
