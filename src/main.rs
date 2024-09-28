use alloy::{
    hex,
    network::EthereumWallet,
    primitives::{Address, U256},
    providers::ProviderBuilder,
    signers::local::PrivateKeySigner,
    transports::http::reqwest::Url,
};
use axum::{
    extract::State,
    http::{header, HeaderValue, Method},
    response::{Html, IntoResponse, Json},
    routing::{get, post},
    Router,
};
use clap::Parser;
use hypernode::core::{EvmHttpProvider, RiftExchange};
use serde::{Deserialize, Serialize};
use std::{
    str::FromStr,
    sync::Arc,
};
use tower_http::cors::CorsLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use ts_rs::TS;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
pub struct Args {
    /// Ethereum RPC URL for broadcasting transactions
    #[arg(short, long, env)]
    pub evm_http_rpc: String,

    /// Ethereum private key for signing transactions
    #[arg(short, long, env)]
    pub private_key: String,

    /// Rift Exchange contract address
    #[arg(short, long, env)]
    pub rift_exchange_address: String,
}

#[derive(Serialize, Deserialize, TS)]
#[ts(export)]
struct ReservationByPaymasterRequest {
    sender: String,
    vault_indexes_to_reserve: Vec<String>,
    amounts_to_reserve: Vec<String>,
    eth_payout_address: String,
    total_sats_input_inlcuding_proxy_fee: String,
    expired_swap_reservation_indexes: Vec<String>,
}

#[derive(Serialize, Deserialize, TS)]
#[ts(export)]
struct ReservationByPaymasterResponse {
    status: bool,
    tx_hash: Option<String>,
}

#[derive(Clone)]
struct AppState {
    contract: Arc<hypernode::core::RiftExchangeHttp>,
}

#[tokio::main]
async fn main() {
    dotenv::dotenv().ok();
    let args = Args::parse();
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("{}=trace", env!("CARGO_CRATE_NAME")).into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();
    let private_key: [u8; 32] = hex::decode(args.private_key.trim_start_matches("0x")).unwrap()
        [..32]
        .try_into()
        .unwrap();

    let provider: Arc<EvmHttpProvider> = Arc::new(
        ProviderBuilder::new()
            .with_recommended_fillers()
            .wallet(EthereumWallet::from(
                PrivateKeySigner::from_bytes(&private_key.into()).unwrap(),
            ))
            .on_http(args.evm_http_rpc.parse::<Url>().unwrap()),
    );

    let state = AppState {
        contract: Arc::new(RiftExchange::new(
            alloy::primitives::Address::from_str(&args.rift_exchange_address).unwrap(),
            provider.clone(),
        )),
    };

    let origins = [
        "http://localhost:3000".parse::<HeaderValue>().unwrap(),
        "https://rift.exchange".parse().unwrap()
    ];

    let app = Router::new()
        .route("/", get(index))
        .route("/reserve_by_paymaster", post(reserve_paymaster))
        .layer(
            CorsLayer::new()
                .allow_origin(origins)
                .allow_methods([Method::GET, Method::POST])
                .allow_headers(vec![header::CONTENT_TYPE]),
        )
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:4000")
        .await
        .unwrap();
    tracing::debug!("Reservation Paymaster API on http://{}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}

async fn index() -> Html<&'static str> {
    Html(std::include_str!("../index.html"))
}

async fn reserve_paymaster(
    State(state): State<AppState>,
    Json(request): Json<ReservationByPaymasterRequest>,
) -> impl IntoResponse {
    let result = process_reservation(state, request).await;

    Json(match result {
        Ok(tx_hash) => ReservationByPaymasterResponse {
            status: true,
            tx_hash: Some(tx_hash),
        },
        Err(_) => ReservationByPaymasterResponse {
            status: false,
            tx_hash: None,
        },
    })
}

async fn process_reservation(
    state: AppState,
    request: ReservationByPaymasterRequest,
) -> Result<String, Box<dyn std::error::Error>> {
    let sender = Address::from_str(&request.sender)?;
    let vault_indexes_to_reserve: Vec<U256> = request
        .vault_indexes_to_reserve
        .iter()
        .map(|x| U256::from_str(x))
        .collect::<Result<Vec<U256>, _>>()?;
    let amounts_to_reserve: Vec<U256> = request
        .amounts_to_reserve
        .iter()
        .map(|x| U256::from_str(x))
        .collect::<Result<Vec<U256>, _>>()?;
    let eth_payout_address = Address::from_str(&request.eth_payout_address)?;
    let total_sats_input_including_proxy_fee =
        U256::from_str(&request.total_sats_input_inlcuding_proxy_fee)?;
    let expired_swap_reservation_indexes: Vec<U256> = request
        .expired_swap_reservation_indexes
        .iter()
        .map(|x| U256::from_str(x))
        .collect::<Result<Vec<U256>, _>>()?;

    let tx_future = state.contract.reserveLiquidity(
        sender,
        vault_indexes_to_reserve,
        amounts_to_reserve,
        eth_payout_address,
        total_sats_input_including_proxy_fee,
        expired_swap_reservation_indexes,
    );

    let tx = tx_future.send().await.unwrap();
    let tx_hash = tx.tx_hash().clone().to_string();
    tracing::info!("Reserving w/ transaction hash: {}", tx_hash);
    Ok(tx_hash)
}
