# Rift Reservation Paymaster
Pay for reservations on behalf of users.

## Build Docker Image 
```bash
source .env && docker build \
  --build-arg EVM_HTTP_RPC="$EVM_HTTP_RPC" \
  --build-arg PRIVATE_KEY="$PRIVATE_KEY" \
  --build-arg RIFT_EXCHANGE_ADDRESS="$RIFT_EXCHANGE_ADDRESS" \
  -t reservation-paymaster .
```
