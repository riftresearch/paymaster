# Stage 1: Build the application using the Rust slim image
FROM rust:1.81-slim-bullseye AS builder

# Set the working directory inside the container
WORKDIR /usr/src/app

# Install necessary packages for building with OpenSSL, git, and handling submodules
RUN apt-get update && apt-get install -y \
    git \
    pkg-config \
    libssl-dev \
    build-essential

# Clone the main repository and initialize submodules
RUN git clone --recursive https://github.com/rift-labs-inc/paymaster /usr/src/app

# Build the actual project using the specified Rust version
RUN cargo build --release

# Stage 2: Create the runtime image using debian:bullseye-slim
FROM debian:bullseye-slim

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
