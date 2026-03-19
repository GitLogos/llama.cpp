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

# Fixed: Combined the broken COPY command
COPY . /src

# Fixed: Combined the broken cmake command
RUN cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_OPENVINO=ON \
    && cmake --build build --target llama-server -j"$(nproc)"

# Fixed: Combined the broken ldd command
RUN ldd /src/build/bin/llama-server || true


# -----------------------------------------------------------------------------
# Runtime image: OpenVINO base + copy llama-server AND its shared libraries
# -----------------------------------------------------------------------------
# Optimized: Swapped to the much smaller runtime image
FROM openvino/ubuntu22_runtime:latest AS runtime

ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /app

USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Copy server binary
COPY --from=build /src/build/bin/llama-server /app/llama-server

# Copy all llama.cpp-built shared libs so libmtmd.so.0 is present.
# These typically live under build/lib (and sometimes build/bin depending on layout).
RUN mkdir -p /app/lib
# Added '|| true' to prevent build failures if no .so files are found
COPY --from=build /src/build/lib/*.so* /app/lib/ 2>/dev/null || true
COPY --from=build /src/build/bin/*.so* /app/lib/ 2>/dev/null || true

# Ensure the dynamic linker can find them
RUN echo "/app/lib" > /etc/ld.so.conf.d/llama-local.conf && ldconfig

# Fixed: Combined the broken ldd command
RUN ldd /app/llama-server | sed -n '1,200p'

ENV LLAMA_ARG_HOST=0.0.0.0
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/llama-server"]
