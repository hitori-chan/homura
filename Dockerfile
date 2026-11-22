# syntax=docker/dockerfile:1
# Static musl binaries in scratch images. Targets: server, bot.
#   docker build --target server -t homura .
#   docker build --target bot -t homura-bot .

# Debian's compiler, not Alpine's, whose musl allocator makes it several times slower. The
# programs are still built for musl, so they're static.
FROM rust:1.100-slim AS toolchain
RUN apt-get update && apt-get install -y --no-install-recommends musl-tools && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# The toolchain rust-toolchain.toml pins, which CI checks with, even once the image's tag moves on.
COPY rust-toolchain.toml .
RUN rustup toolchain install --no-self-update && rustup target add "$(uname -m)-unknown-linux-musl"
COPY . .
RUN mkdir /data

# Each image builds only its program: built together, the bot would get every feature of its
# dependencies that the server turns on. Downloaded and compiled crates stay in caches between
# builds, so only what changed compiles again, even after Cargo.lock changes. The sources are
# touched because cargo goes by file times, and copied files can look older than the cached build.
FROM toolchain AS build-server
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    find server/src server/templates server/static -type f -exec touch {} + \
 && target="$(uname -m)-unknown-linux-musl" \
 && cargo build --release --locked --target "$target" -p server \
 && cp "target/$target/release/server" /

FROM toolchain AS build-bot
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    find bot/src -type f -exec touch {} + \
 && target="$(uname -m)-unknown-linux-musl" \
 && cargo build --release --locked --target "$target" -p bot \
 && cp "target/$target/release/bot" /

FROM scratch AS server
COPY --from=build-server /server /server
COPY --from=toolchain --chown=65532:65532 /data /data
USER 65532:65532
WORKDIR /data
ENV DATA_DIR=/data
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD ["/server", "healthcheck"]
ENTRYPOINT ["/server"]

FROM scratch AS bot
COPY --from=build-bot /bot /bot
COPY --from=toolchain --chown=65532:65532 /data /data
USER 65532:65532
WORKDIR /data
ENTRYPOINT ["/bot"]
CMD ["/bot.toml"]
