# Stage 1: Build the application using the Rust slim image
FROM rust:1.81-slim-bullseye AS builder

# Set the working directory inside the container
WORKDIR /usr/src/app

# Install necessary packages for building with OpenSSL and git to handle submodules
RUN apt-get update && apt-get install -y \
    git \
    pkg-config \
    libssl-dev \
    build-essential

# Copy the Cargo files and project structure
COPY Cargo.toml Cargo.lock ./

# Copy the submodule (hypernode) Cargo files first for caching purposes
COPY hypernode/Cargo.toml hypernode/Cargo.lock ./hypernode/

# Copy the entire project, excluding the TypeScript bindings
COPY . .

# Initialize and update git submodules
COPY .git .git
RUN git submodule update --init --recursive

# Build the actual project using the specified Rust version
RUN cargo build --release

# Stage 2: Create the runtime image
FROM debian:buster-slim

# Install necessary dependencies (libssl-dev for OpenSSL runtime)
RUN apt-get update && apt-get install -y \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /usr/local/bin

# Copy the compiled binary from the build stage
COPY --from=builder /usr/src/app/target/release/reservation-paymaster .

# Accept build-time arguments and convert them to environment variables
ARG EVM_HTTP_RPC
ARG PRIVATE_KEY
ARG RIFT_EXCHANGE_ADDRESS

# Pass the arguments as environment variables to the running container
ENV EVM_HTTP_RPC=$EVM_HTTP_RPC
ENV PRIVATE_KEY=$PRIVATE_KEY
ENV RIFT_EXCHANGE_ADDRESS=$RIFT_EXCHANGE_ADDRESS
ENV RUST_LOG=debug

# Expose port 4000
EXPOSE 4000

# Specify the command to run the app and ensure it picks up environment variables
CMD ["./reservation-paymaster"]

