# First, build the application in the `/app` directory.
# See `Dockerfile` for details.
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

# Disable Python downloads, because we want to use the system interpreter
# across both images. If using a managed Python version, it needs to be
# copied from the build image into the final image; see `standalone.Dockerfile`
# for an example.
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Install build dependencies
RUN apt-get update \
  && apt-get install -y libpq-dev gcc \
  && rm -rf /var/lib/apt/lists/*

# Copy dependency files first for better caching
COPY uv.lock pyproject.toml ./

# Install dependencies without installing the project itself
RUN --mount=type=cache,target=/root/.cache/uv \
  uv sync --frozen --no-install-project --no-dev

# Copy the rest of the application
COPY . .

# Install the project
RUN --mount=type=cache,target=/root/.cache/uv \
  uv sync --frozen --no-dev


FROM python:3.12-slim-bookworm
# It is important to use the image that matches the builder, as the path to the
# Python executable must be the same, e.g., using `python:3.11-slim-bookworm`
# will fail.

# Create app user
RUN groupadd --gid 1000 app && useradd --uid 1000 --gid app --shell /bin/bash --create-home app

COPY --from=builder --chown=app:app /app /app

ENV PATH="/app/.venv/bin:$PATH"

ARG TARGETPLATFORM
ARG BUILDPLATFORM
LABEL org.opencontainers.image.description="Postgres MCP Agent - Multi-architecture container (${TARGETPLATFORM})"
LABEL org.opencontainers.image.source="https://github.com/crystaldba/postgres-mcp"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.vendor="Crystal DBA"
LABEL org.opencontainers.image.url="https://www.crystaldba.ai"

# Install runtime system dependencies
RUN apt-get update && apt-get install -y \
  libpq-dev \
  iputils-ping \
  dnsutils \
  net-tools \
  && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /app/
RUN chmod +x /app/docker-entrypoint.sh

# Switch to app user for security
USER app

# Expose the SSE port
EXPOSE 8000

# Run the postgres-mcp server
# Users can pass a database URI or individual connection arguments:
#   docker run -it --rm postgres-mcp postgres://user:pass@host:port/dbname
#   docker run -it --rm postgres-mcp -h myhost -p 5432 -U myuser -d mydb
ENTRYPOINT ["/app/docker-entrypoint.sh", "postgres-mcp"]
CMD ["--transport", "sse", "--sse-host", "0.0.0.0", "--sse-port", "8000"]
