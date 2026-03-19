# -----------------------------------------------------------------------------
# Build llama-server with OpenVINO backend using OpenVINO's Ubuntu 22.04 dev image
# -----------------------------------------------------------------------------
FROM openvino/ubuntu22_dev:latest AS build

ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /src

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates cmake ninja-build build-essential pkg-config curl \
    && rm -rf /var/lib/apt/lists/*

COPY . /src

RUN cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_OPENVINO=ON \
    && cmake --build build --target llama-server -j"$(nproc)"

# Gather all generated shared libraries into one directory for easy copying
RUN mkdir -p /src/build-libs \
    && find /src/build/lib /src/build/bin -maxdepth 1 -name "*.so*" -exec cp {} /src/build-libs/ \; 2>/dev/null || true


# -----------------------------------------------------------------------------
# Runtime image: OpenVINO base + copy llama-server AND its shared libraries
# -----------------------------------------------------------------------------
FROM openvino/ubuntu22_runtime:latest AS runtime

ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /app

USER root
# FIX: Added libgomp1 (required for OpenMP multi-threading) 
# and libatomic1 (common C++ dependency)
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      libgomp1 \
      libatomic1 \
    && rm -rf /var/lib/apt/lists/*

# Copy server binary
COPY --from=build /src/build/bin/llama-server /app/llama-server

# Copy the gathered llama.cpp shared libs
COPY --from=build /src/build-libs/ /app/lib/

# Ensure the dynamic linker can find them
RUN echo "/app/lib" > /etc/ld.so.conf.d/llama-local.conf && ldconfig

# Verification: Show dependencies to catch missing ones early in logs
RUN ldd /app/llama-server | sed -n '1,100p'

ENV LLAMA_ARG_HOST=0.0.0.0
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/llama-server"]
