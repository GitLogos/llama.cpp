# -----------------------------------------------------------------------------
# Build llama-server with OpenVINO backend using OpenVINO's Ubuntu 22.04 dev image
# -----------------------------------------------------------------------------
FROM openvino/ubuntu22_dev:latest AS build

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /src

# Ensure we're root for installs (some images default to non-root)
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      ca-certificates \
      cmake \
      ninja-build \
      build-essential \
      pkg-config \
      curl \
    && rm -rf /var/lib/apt/lists/*

COPY . /src

RUN cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_OPENVINO=ON \
    && cmake --build build --target llama-server -j"$(nproc)"

# -----------------------------------------------------------------------------
# Runtime image: keep OpenVINO runtime + GPU enablement from the OpenVINO base image
# -----------------------------------------------------------------------------
FROM openvino/ubuntu22_dev:latest AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Ensure we're root for apt
USER root

# Install curl for HEALTHCHECK
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
    && rm -rf /var/lib/apt/lists/*

# Copy the built server binary
COPY --from=build /src/build/bin/llama-server /app/llama-server

WORKDIR /app

ENV LLAMA_ARG_HOST=0.0.0.0
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/llama-server"]
