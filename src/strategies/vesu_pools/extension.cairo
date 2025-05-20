#[starknet::contract]
mod DefaultExtensionPO {
    use alexandria_math::i257::{i257, I257Trait};
    use starknet::{
        ContractAddress, get_contract_address, get_caller_address, event::EventEmitter, contract_address_const
    };
    use core::num::traits::Zero;
    use strkfarm_contracts::strategies::vesu_pools::interface::{UnderlyingTokens, ICustomAssets, AssetType};
    use strkfarm_contracts::strategies::cl_vault::interface::{IClVaultDispatcher,IClVaultDispatcherTrait};
    use strkfarm_contracts::interfaces::IERC4626::{
        IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait
    };
    use strkfarm_contracts::helpers::{ERC20Helper, pow};
    use vesu::{
        map_list::{map_list_component, map_list_component::MapListTrait},
        data_model::{
            Amount, UnsignedAmount, AssetParams, AssetPrice, LTVParams, Context, LTVConfig, ModifyPositionParams,
            AmountDenomination, AmountType, DebtCapParams
        },
        units::{INFLATION_FEE, SCALE},
        singleton::{ISingletonDispatcher, ISingletonDispatcherTrait},
        vendor::{
            erc20::{
                {ERC20ABIDispatcher as IERC20Dispatcher, ERC20ABIDispatcherTrait}
            },
            pragma::{
                DataType, IPragmaABIDispatcher, IPragmaABIDispatcherTrait
            }
        },
        extension::{
            default_extension_po::{
                LiquidationParams, ShutdownParams, PragmaOracleParams, ITimestampManagerCallback, IDefaultExtension,
                FeeParams, VTokenParams, IDefaultExtensionCallback, ITokenizationCallback
            },
            interface::{IExtension},
            components::{
                interest_rate_model::{
                    InterestRateConfig, interest_rate_model_component,
                    interest_rate_model_component::InterestRateModelTrait
                },
                position_hooks::{
                    position_hooks_component, position_hooks_component::PositionHooksTrait, ShutdownStatus,
                    ShutdownMode, ShutdownConfig, LiquidationConfig, Pair
                },
                pragma_oracle::{pragma_oracle_component, pragma_oracle_component::PragmaOracleTrait, OracleConfig},
                fee_model::{fee_model_component, fee_model_component::FeeModelTrait, FeeConfig},
                tokenization::{tokenization_component, tokenization_component::TokenizationTrait}
            }
        },
    };

    component!(path: position_hooks_component, storage: position_hooks, event: PositionHooksEvents);
    component!(path: interest_rate_model_component, storage: interest_rate_model, event: InterestRateModelEvents);
    component!(path: pragma_oracle_component, storage: pragma_oracle, event: PragmaOracleEvents);
    component!(path: map_list_component, storage: timestamp_manager, event: MapListEvents);
    component!(path: fee_model_component, storage: fee_model, event: FeeModelEvents);
    component!(path: tokenization_component, storage: tokenization, event: TokenizationEvents);


    #[storage]
    struct Storage {
        // address of the singleton contract
        singleton: ContractAddress,
        // tracks the owner for each pool
        owner: LegacyMap::<felt252, ContractAddress>,
        // tracks the name for each pool
        pool_names: LegacyMap::<felt252, felt252>,
        // storage for custom assets like Ekubo xSTRK/STRK
        is_custom_asset: LegacyMap::<ContractAddress, AssetType>,
        // storage for custom assets' descriptive tokens 
        custom_assets: LegacyMap::<ContractAddress, (ContractAddress, ContractAddress)>,
        // storage for the position hooks component
        #[substorage(v0)]
        position_hooks: position_hooks_component::Storage,
        // storage for the interest rate model component
        #[substorage(v0)]
        interest_rate_model: interest_rate_model_component::Storage,
        // storage for the pragma oracle component
        #[substorage(v0)]
        pragma_oracle: pragma_oracle_component::Storage,
        // storage for the timestamp manager component
        #[substorage(v0)]
        timestamp_manager: map_list_component::Storage,
        // storage for the fee model component
        #[substorage(v0)]
        fee_model: fee_model_component::Storage,
        // storage for the tokenization component
        #[substorage(v0)]
        tokenization: tokenization_component::Storage,
    }

    #[derive(Drop, starknet::Event)]
    struct SetAssetParameter {
        #[key]
        pool_id: felt252,
        #[key]
        asset: ContractAddress,
        #[key]
        parameter: felt252,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct SetPoolOwner {
        #[key]
        pool_id: felt252,
        #[key]
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PositionHooksEvents: position_hooks_component::Event,
        InterestRateModelEvents: interest_rate_model_component::Event,
        PragmaOracleEvents: pragma_oracle_component::Event,
        MapListEvents: map_list_component::Event,
        FeeModelEvents: fee_model_component::Event,
        TokenizationEvents: tokenization_component::Event,
        SetAssetParameter: SetAssetParameter,
        SetPoolOwner: SetPoolOwner,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        singleton: ContractAddress,
        oracle_address: ContractAddress,
        summary_address: ContractAddress,
        v_token_class_hash: felt252,
    ) {
        self.singleton.write(singleton);
        self.pragma_oracle.set_oracle(oracle_address);
        self.pragma_oracle.set_summary_address(summary_address);
        self.tokenization.set_v_token_class_hash(v_token_class_hash);
    }

    #[abi(embed_v0)]
    impl CustomAssetsImpl of ICustomAssets<ContractState> {
        fn is_custom_asset(self: @ContractState, asset: ContractAddress) -> AssetType {
            self.is_custom_asset.read(asset)
        }

        fn underlying_assets(self: @ContractState, asset: ContractAddress) -> (ContractAddress, ContractAddress) {
            self.custom_assets.read(asset)
        }

        fn set_custom_asset(ref self: ContractState, pool_id: felt252, asset: ContractAddress, asset_type: AssetType) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.is_custom_asset.write(asset, asset_type);
        }

        fn set_underlying_assets(
            ref self: ContractState,
            pool_id: felt252,
            custom_asset: ContractAddress,  
            asset0: ContractAddress,
            asset1: ContractAddress
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.custom_assets.write(custom_asset, (asset0, asset1));
        }
    }

    impl DefaultExtensionCallbackImpl of IDefaultExtensionCallback<ContractState> {
        fn singleton(self: @ContractState) -> ContractAddress {
            self.singleton.read()
        }
    }

    impl TimestampManagerCallbackImpl of ITimestampManagerCallback<ContractState> {
        /// See timestamp_manager.contains()
        fn contains(self: @ContractState, pool_id: felt252, item: u64) -> bool {
            self.timestamp_manager.contains(pool_id, item)
        }
        /// See timestamp_manager.push_front()
        fn push_front(ref self: ContractState, pool_id: felt252, item: u64) {
            self.timestamp_manager.push_front(pool_id, item)
        }
        /// See timestamp_manager.remove()
        fn remove(ref self: ContractState, pool_id: felt252, item: u64) {
            self.timestamp_manager.remove(pool_id, item)
        }
        /// See timestamp_manager.first()
        fn first(self: @ContractState, pool_id: felt252) -> u64 {
            self.timestamp_manager.first(pool_id)
        }
        /// See timestamp_manager.last()
        fn last(self: @ContractState, pool_id: felt252) -> u64 {
            self.timestamp_manager.last(pool_id)
        }
        /// See timestamp_manager.previous()
        fn previous(self: @ContractState, pool_id: felt252, item: u64) -> u64 {
            self.timestamp_manager.previous(pool_id, item)
        }
        /// See timestamp_manager.all()
        fn all(self: @ContractState, pool_id: felt252) -> Array<u64> {
            self.timestamp_manager.all(pool_id)
        }
    }

    impl TokenizationCallbackImpl of ITokenizationCallback<ContractState> {
        /// See tokenization.v_token_for_collateral_asset()
        fn v_token_for_collateral_asset(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress
        ) -> ContractAddress {
            self.tokenization.v_token_for_collateral_asset(pool_id, collateral_asset)
        }
        /// See tokenization.mint_or_burn_v_token()
        fn mint_or_burn_v_token(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            user: ContractAddress,
            amount: i257
        ) {
            self.tokenization.mint_or_burn_v_token(pool_id, collateral_asset, user, amount)
        }
    }

    /// Helper method for transferring an amount of an asset from one address to another. Reverts if the transfer fails.
    /// # Arguments
    /// * `asset` - address of the asset
    /// * `sender` - address of the sender of the assets
    /// * `to` - address of the receiver of the assets
    /// * `amount` - amount of assets to transfer [asset scale]
    /// * `is_legacy` - whether the asset is a legacy ERC20 (only supporting camelCase instead of snake_case)
    fn transfer_asset(
        asset: ContractAddress, sender: ContractAddress, to: ContractAddress, amount: u256, is_legacy: bool
    ) {
        let erc20 = IERC20Dispatcher { contract_address: asset };
        if sender == get_contract_address() {
            assert!(erc20.transfer(to, amount), "transfer-failed");
        } else if is_legacy {
            assert!(erc20.transferFrom(sender, to, amount), "transferFrom-failed");
        } else {
            assert!(erc20.transfer_from(sender, to, amount), "transfer-from-failed");
        }
    }

    #[abi(embed_v0)]
    impl DefaultExtensionImpl of IDefaultExtension<ContractState> {
        /// Returns the name of a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `name` - name of the pool
        fn pool_name(self: @ContractState, pool_id: felt252) -> felt252 {
            self.pool_names.read(pool_id)
        }

        /// Returns the owner of a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `owner` - address of the owner
        fn pool_owner(self: @ContractState, pool_id: felt252) -> ContractAddress {
            self.owner.read(pool_id)
        }

        /// Returns the address of the pragma oracle contract
        /// # Returns
        /// * `oracle_address` - address of the pragma oracle contract
        fn pragma_oracle(self: @ContractState) -> ContractAddress {
            self.pragma_oracle.oracle_address()
        }

        /// Returns the address of the pragma summary contract
        /// # Returns
        /// * `summary_address` - address of the pragma summary contract
        fn pragma_summary(self: @ContractState) -> ContractAddress {
            self.pragma_oracle.summary_address()
        }

        /// Returns the oracle configuration for a given pool and asset
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `oracle_config` - oracle configuration
        fn oracle_config(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> OracleConfig {
            self.pragma_oracle.oracle_configs.read((pool_id, asset))
        }

        /// Returns the fee configuration for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `fee_config` - fee configuration
        fn fee_config(self: @ContractState, pool_id: felt252) -> FeeConfig {
            self.fee_model.fee_configs.read(pool_id)
        }

        /// Returns the debt cap for a given asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `debt_cap` - debt cap
        fn debt_caps(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> u256 {
            self.position_hooks.debt_caps.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the interest rate configuration for a given pool and asset
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `interest_rate_config` - interest rate configuration
        fn interest_rate_config(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> InterestRateConfig {
            self.interest_rate_model.interest_rate_configs.read((pool_id, asset))
        }

        /// Returns the liquidation configuration for a given pool and pairing of assets
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `liquidation_config` - liquidation configuration
        fn liquidation_config(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> LiquidationConfig {
            self.position_hooks.liquidation_configs.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the shutdown configuration for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `recovery_period` - recovery period
        /// * `subscription_period` - subscription period
        fn shutdown_config(self: @ContractState, pool_id: felt252) -> ShutdownConfig {
            self.position_hooks.shutdown_configs.read(pool_id)
        }

        /// Returns the shutdown LTV configuration for a given pair in a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_ltv_config` - shutdown LTV configuration
        fn shutdown_ltv_config(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> LTVConfig {
            self.position_hooks.shutdown_ltv_configs.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the total (sum of all positions) collateral shares and nominal debt balances for a given pair
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `total_collateral_shares` - total collateral shares
        /// * `total_nominal_debt` - total nominal debt
        fn pairs(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> Pair {
            self.position_hooks.pairs.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the timestamp at which a given pair in a given pool transitioned to recovery mode
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `violation_timestamp` - timestamp at which the pair transitioned to recovery mode
        fn violation_timestamp_for_pair(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> u64 {
            self.position_hooks.violation_timestamps.read((pool_id, collateral_asset, debt_asset))
        }

        /// Returns the count of how many pairs in a given pool transitioned to recovery mode at a given timestamp
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `violation_timestamp` - timestamp at which the pair transitioned to recovery mode
        /// # Returns
        /// * `count_at_violation_timestamp_timestamp` - count of how many pairs transitioned to recovery mode at that timestamp
        fn violation_timestamp_count(self: @ContractState, pool_id: felt252, violation_timestamp: u64) -> u128 {
            self.position_hooks.violation_timestamp_counts.read((pool_id, violation_timestamp))
        }

        /// Returns the oldest timestamp at which a pair in a given pool transitioned to recovery mode
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// # Returns
        /// * `oldest_violation_timestamp` - oldest timestamp at which a pair transitioned to recovery mode
        fn oldest_violation_timestamp(self: @ContractState, pool_id: felt252) -> u64 {
            self.timestamp_manager.last(pool_id)
        }

        /// Returns the next (older) violation timestamp for a given violation timestamp for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `violation_timestamp` - violation timestamp
        /// # Returns
        /// * `next_violation_timestamp` - next (older) violation timestamp
        fn next_violation_timestamp(self: @ContractState, pool_id: felt252, violation_timestamp: u64) -> u64 {
            self.timestamp_manager.next(pool_id, violation_timestamp.into())
        }

        /// Returns the address of the vToken deployed for the collateral asset for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// # Returns
        /// * `v_token` - address of the vToken
        fn v_token_for_collateral_asset(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress
        ) -> ContractAddress {
            self.tokenization.v_token_for_collateral_asset(pool_id, collateral_asset)
        }

        /// Returns the default pairing (collateral asset, debt asset) used for 
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `v_token` - address of the vToken
        /// # Returns
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        fn collateral_asset_for_v_token(
            self: @ContractState, pool_id: felt252, v_token: ContractAddress
        ) -> ContractAddress {
            self.tokenization.collateral_asset_for_v_token(pool_id, v_token)
        }

        /// Creates a new pool
        /// # Arguments
        /// * `name` - name of the pool
        /// * `asset_params` - asset parameters
        /// * `v_token_params` - vToken parameters
        /// * `ltv_params` - loan-to-value parameters
        /// * `interest_rate_params` - interest rate model parameters
        /// * `pragma_oracle_params` - pragma oracle parameters
        /// * `liquidation_params` - liquidation parameters
        /// * `debt_caps` - debt caps
        /// * `shutdown_params` - shutdown parameters
        /// * `fee_params` - fee model parameters
        /// # Returns
        /// * `pool_id` - id of the pool
        fn create_pool(
            ref self: ContractState,
            name: felt252,
            mut asset_params: Span<AssetParams>,
            mut v_token_params: Span<VTokenParams>,
            mut ltv_params: Span<LTVParams>,
            mut interest_rate_configs: Span<InterestRateConfig>,
            mut pragma_oracle_params: Span<PragmaOracleParams>,
            mut liquidation_params: Span<LiquidationParams>,
            mut debt_caps: Span<DebtCapParams>,
            shutdown_params: ShutdownParams,
            fee_params: FeeParams,
            owner: ContractAddress
        ) -> felt252 {
            assert!(asset_params.len() > 0, "empty-asset-params");
            // assert that all arrays have equal length
            assert!(asset_params.len() == interest_rate_configs.len(), "interest-rate-params-mismatch");
            assert!(asset_params.len() == pragma_oracle_params.len(), "pragma-oracle-params-mismatch");
            assert!(asset_params.len() == v_token_params.len(), "v-token-params-mismatch");
            // create the pool in the singleton
            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            let pool_id = singleton.create_pool(asset_params, ltv_params, get_contract_address());

            // set the pool name
            self.pool_names.write(pool_id, name);

            // set the pool owner
            self.owner.write(pool_id, owner);
            let mut asset_params_copy = asset_params;
            let mut i = 0;
            while !asset_params_copy
                .is_empty() {
                    let asset_params = *asset_params_copy.pop_front().unwrap();
                    let asset = asset_params.asset;

                    // set the oracle config
                    let params = *pragma_oracle_params.pop_front().unwrap();
                    let PragmaOracleParams { pragma_key,
                    timeout,
                    number_of_sources,
                    start_time_offset,
                    time_window,
                    aggregation_mode } =
                        params;
                    self
                        .pragma_oracle
                        .set_oracle_config(
                            pool_id,
                            asset,
                            OracleConfig {
                                pragma_key, timeout, number_of_sources, start_time_offset, time_window, aggregation_mode
                            }
                        );

                    // set the interest rate model configuration
                    let interest_rate_config = *interest_rate_configs.pop_front().unwrap();
                    self.interest_rate_model.set_interest_rate_config(pool_id, asset, interest_rate_config);
                    let v_token_config = *v_token_params.at(i);
                    let VTokenParams { v_token_name, v_token_symbol } = v_token_config;

                    // deploy the vToken for the the collateral asset
                    self.tokenization.create_v_token(pool_id, asset, v_token_name, v_token_symbol);
                    // burn inflation fee
                    let asset = IERC20Dispatcher { contract_address: asset };
                    let bal = asset.balance_of(get_caller_address());
                    transfer_asset(
                        asset.contract_address,
                        get_caller_address(),
                        get_contract_address(),
                        INFLATION_FEE,
                        asset_params.is_legacy
                    );
                    assert!(asset.approve(singleton.contract_address, INFLATION_FEE), "approve-failed");
                    singleton
                        .modify_position(
                            ModifyPositionParams {
                                pool_id,
                                collateral_asset: asset.contract_address,
                                debt_asset: Zero::zero(),
                                user: contract_address_const::<'ZERO'>(),
                                collateral: Amount {
                                    amount_type: AmountType::Delta,
                                    denomination: AmountDenomination::Assets,
                                    value: I257Trait::new(INFLATION_FEE, false),
                                },
                                debt: Default::default(),
                                data: ArrayTrait::new().span()
                            }
                        );

                    i += 1;
                };

            // set the liquidation config for each pair
            let mut liquidation_params = liquidation_params;
            while !liquidation_params
                .is_empty() {
                    let params = *liquidation_params.pop_front().unwrap();
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self
                        .position_hooks
                        .set_liquidation_config(
                            pool_id,
                            collateral_asset,
                            debt_asset,
                            LiquidationConfig { liquidation_factor: params.liquidation_factor }
                        );
                };
            // set the debt caps for each pair
            let mut debt_caps = debt_caps;
            while !debt_caps
                .is_empty() {
                    let params = *debt_caps.pop_front().unwrap();
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self.position_hooks.set_debt_cap(pool_id, collateral_asset, debt_asset, params.debt_cap);
                };
            // set the max shutdown LTVs for each pair
            let mut shutdown_ltv_params = shutdown_params.ltv_params;
            while !shutdown_ltv_params
                .is_empty() {
                    let params = *shutdown_ltv_params.pop_front().unwrap();
                    let collateral_asset = *asset_params.at(params.collateral_asset_index).asset;
                    let debt_asset = *asset_params.at(params.debt_asset_index).asset;
                    self
                        .position_hooks
                        .set_shutdown_ltv_config(
                            pool_id, collateral_asset, debt_asset, LTVConfig { max_ltv: params.max_ltv }
                        );
                };
            // set the shutdown config
            let ShutdownParams { recovery_period, subscription_period, .. } = shutdown_params;
            self.position_hooks.set_shutdown_config(pool_id, ShutdownConfig { recovery_period, subscription_period });

            // set the fee config
            self.fee_model.set_fee_config(pool_id, FeeConfig { fee_recipient: fee_params.fee_recipient });

            pool_id
        }

        /// Adds an asset to a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset_params` - asset parameters
        /// * `v_token_params` - vToken parameters
        /// * `interest_rate_model` - interest rate model
        /// * `pragma_oracle_params` - pragma oracle parameters
        fn add_asset(
            ref self: ContractState,
            pool_id: felt252,
            asset_params: AssetParams,
            v_token_params: VTokenParams,
            interest_rate_config: InterestRateConfig,
            pragma_oracle_params: PragmaOracleParams
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            let asset = asset_params.asset;

            // set the oracle config
            self
                .pragma_oracle
                .set_oracle_config(
                    pool_id,
                    asset,
                    OracleConfig {
                        pragma_key: pragma_oracle_params.pragma_key,
                        timeout: pragma_oracle_params.timeout,
                        number_of_sources: pragma_oracle_params.number_of_sources,
                        start_time_offset: pragma_oracle_params.start_time_offset,
                        time_window: pragma_oracle_params.time_window,
                        aggregation_mode: pragma_oracle_params.aggregation_mode
                    }
                );

            // set the interest rate model configuration
            self.interest_rate_model.set_interest_rate_config(pool_id, asset, interest_rate_config);

            // deploy the vToken for the the collateral asset
            let VTokenParams { v_token_name, v_token_symbol } = v_token_params;
            self.tokenization.create_v_token(pool_id, asset, v_token_name, v_token_symbol);

            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            singleton.set_asset_config(pool_id, asset_params);

            // burn inflation fee
            let asset = IERC20Dispatcher { contract_address: asset };
            transfer_asset(
                asset.contract_address,
                get_caller_address(),
                get_contract_address(),
                INFLATION_FEE,
                asset_params.is_legacy
            );
            assert!(asset.approve(singleton.contract_address, INFLATION_FEE), "approve-failed");
            singleton
                .modify_position(
                    ModifyPositionParams {
                        pool_id,
                        collateral_asset: asset.contract_address,
                        debt_asset: Zero::zero(),
                        user: contract_address_const::<'ZERO'>(),
                        collateral: Amount {
                            amount_type: AmountType::Delta,
                            denomination: AmountDenomination::Assets,
                            value: I257Trait::new(INFLATION_FEE, false),
                        },
                        debt: Default::default(),
                        data: ArrayTrait::new().span()
                    }
                );
        }

        /// Sets the debt cap for a given asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `debt_cap` - debt cap
        fn set_debt_cap(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            debt_cap: u256
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.position_hooks.set_debt_cap(pool_id, collateral_asset, debt_asset, debt_cap);
        }

        /// Sets a parameter for a given interest rate configuration for an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_interest_rate_parameter(
            ref self: ContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: u256
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.interest_rate_model.set_interest_rate_parameter(pool_id, asset, parameter, value);
        }

        /// Sets a parameter for a given oracle configuration of an asset in a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter
        fn set_oracle_parameter(
            ref self: ContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: felt252
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.pragma_oracle.set_oracle_parameter(pool_id, asset, parameter, value);
        }

        /// Sets the loan-to-value configuration between two assets (pair) in the pool in the singleton
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `ltv_config` - ltv configuration
        fn set_ltv_config(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            ltv_config: LTVConfig
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            ISingletonDispatcher { contract_address: self.singleton.read() }
                .set_ltv_config(pool_id, collateral_asset, debt_asset, ltv_config);
        }

        /// Sets the liquidation config for a given pair in the pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `liquidation_config` - liquidation config
        fn set_liquidation_config(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            liquidation_config: LiquidationConfig
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.position_hooks.set_liquidation_config(pool_id, collateral_asset, debt_asset, liquidation_config);
        }

        /// Sets a parameter of an asset for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `parameter` - parameter name
        /// * `value` - value of the parameter 
        fn set_asset_parameter(
            ref self: ContractState, pool_id: felt252, asset: ContractAddress, parameter: felt252, value: u256
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            ISingletonDispatcher { contract_address: self.singleton.read() }
                .set_asset_parameter(pool_id, asset, parameter, value);
        }

        /// Sets the shutdown config for a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `shutdown_config` - shutdown config
        fn set_shutdown_config(ref self: ContractState, pool_id: felt252, shutdown_config: ShutdownConfig) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.position_hooks.set_shutdown_config(pool_id, shutdown_config);
        }

        /// Sets the shutdown LTV config for a given pair in the pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// * `shutdown_ltv_config` - shutdown LTV config
        fn set_shutdown_ltv_config(
            ref self: ContractState,
            pool_id: felt252,
            collateral_asset: ContractAddress,
            debt_asset: ContractAddress,
            shutdown_ltv_config: LTVConfig
        ) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.position_hooks.set_shutdown_ltv_config(pool_id, collateral_asset, debt_asset, shutdown_ltv_config);
        }

        /// Sets the owner of a pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `owner` - address of the new owner
        fn set_pool_owner(ref self: ContractState, pool_id: felt252, owner: ContractAddress) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.owner.write(pool_id, owner);
            self.emit(SetPoolOwner { pool_id, owner });
        }

        /// Sets the extension for a pool in the singleton
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `extension` - address of the extension contract
        fn set_extension(ref self: ContractState, pool_id: felt252, extension: ContractAddress) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            singleton.set_extension(pool_id, extension);
        }

        /// Sets the shutdown mode for a given pool and overwrites the inferred shutdown mode
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `shutdown_mode` - shutdown mode
        fn set_shutdown_mode(ref self: ContractState, pool_id: felt252, shutdown_mode: ShutdownMode) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.position_hooks.set_shutdown_mode(pool_id, shutdown_mode);
        }

        /// Returns the shutdown mode for a specific pair in a pool.
        /// To check the shutdown status of the pool, the shutdown mode for all pairs must be checked.
        /// See `shutdown_status` in `position_hooks.cairo`.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_mode` - shutdown mode
        /// * `violation` - whether the pair currently violates any of the invariants (transitioned to recovery mode)
        /// * `previous_violation_timestamp` - timestamp at which the pair previously violated the invariants (transitioned to recovery mode)
        /// * `count_at_violation_timestamp_timestamp` - count of how many pairs violated the invariants at that timestamp
        fn shutdown_status(
            self: @ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> ShutdownStatus {
            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            let mut context = singleton.context_unsafe(pool_id, collateral_asset, debt_asset, Zero::zero());
            self.position_hooks.shutdown_status(ref context)
        }

        /// Updates the shutdown mode for a specific pair in a pool.
        /// See `update_shutdown_status` in `position_hooks.cairo`.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        /// * `debt_asset` - address of the debt asset
        /// # Returns
        /// * `shutdown_mode` - shutdown mode
        fn update_shutdown_status(
            ref self: ContractState, pool_id: felt252, collateral_asset: ContractAddress, debt_asset: ContractAddress
        ) -> ShutdownMode {
            let singleton = ISingletonDispatcher { contract_address: self.singleton.read() };
            let mut context = singleton.context(pool_id, collateral_asset, debt_asset, Zero::zero());
            self.position_hooks.update_shutdown_status(ref context)
        }

        /// Sets the fee configuration for a specific pool.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `fee_config` - new fee configuration parameters
        fn set_fee_config(ref self: ContractState, pool_id: felt252, fee_config: FeeConfig) {
            assert!(get_caller_address() == self.owner.read(pool_id), "caller-not-owner");
            self.fee_model.set_fee_config(pool_id, fee_config);
        }

        /// Claims the fees for a specific pair in a pool.
        /// See `claim_fees` in `fee_model.cairo`.
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `collateral_asset` - address of the collateral asset
        fn claim_fees(ref self: ContractState, pool_id: felt252, collateral_asset: ContractAddress) {
            self.fee_model.claim_fees(pool_id, collateral_asset);
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        /// Returns the address of the singleton contract
        /// # Returns
        /// * `singleton` - address of the singleton contract
        fn singleton(self: @ContractState) -> ContractAddress {
            self.singleton.read()
        }

        /// Returns the price for a given asset in a given pool
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// # Returns
        /// * `AssetPrice` - latest price of the asset and its validity
        // fn price(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> AssetPrice {
        //     let is_custom = self.is_custom_asset.read(asset);
        //     if is_custom {
        //         let ( asset0, asset1 ) = self.custom_assets.read(asset);
        //         println!("asset 0 {:?}", asset0);
        //         println!("asset 1 {:?}", asset1);
        //         let ( asset0_price, _ ) = self.pragma_oracle.price(pool_id, asset0);
        //         let ( asset1_price, _ ) = self.pragma_oracle.price(pool_id, asset1);\

        //         // calc decimals
        //         let dispatcher = IPragmaABIDispatcher { contract_address: self.pragma_oracle() }; 
        //         let asset0_config = self.oracle_config(pool_id, asset0);
        //         let res_token0 = dispatcher.get_data(DataType::SpotEntry(asset0_config.pragma_key), asset0_config.aggregation_mode);
        //         let asset1_config = self.oracle_config(pool_id, asset1);
        //         let res_token1 = dispatcher.get_data(DataType::SpotEntry(asset1_config.pragma_key), asset1_config.aggregation_mode);

        //         let amount = pow::ten_pow(18);
        //         let assets = IClVaultDispatcher {contract_address: asset}
        //             .convert_to_assets(amount);

        //         // calc normalized prices
        //         println!("dec 0 {:?}", res_token0.decimals);
        //         println!("dec 1 {:?}", res_token1.decimals);
        //         let normalized_asset0_price = asset0_price * pow::ten_pow(18 - res_token0.decimals.into());
        //         let normalized_asset1_price = asset1_price * pow::ten_pow(18 - res_token1.decimals.into());

        //         let asset0_value = (assets.amount0 * normalized_asset0_price) / pow::ten_pow(18);
        //         let asset1_value = (assets.amount1 * normalized_asset1_price) / pow::ten_pow(18);
        //         let total_value = asset0_value + asset1_value;

        //         AssetPrice { value: total_value, is_valid: true }
        //         // todo write generalized fn for all tokens with different decimal values
        //         // todo done
        //     } else {
        //         let (value, is_valid) = self.pragma_oracle.price(pool_id, asset);
        //         AssetPrice { value, is_valid }
        //     }
        // }
        fn price(self: @ContractState, pool_id: felt252, asset: ContractAddress) -> AssetPrice {
            let asset_type = self.is_custom_asset.read(asset);
            match asset_type {
                AssetType::BasicERC4626 => {
                    let disp = IERC4626Dispatcher {contract_address: asset};
                    let deposit_asset = disp.asset();
                    let (asset_price, _) = self.pragma_oracle.price(pool_id, deposit_asset);
                    let assets = disp.convert_to_assets(SCALE);
                    let value = (asset_price * assets) / SCALE;
                    return AssetPrice { value, is_valid: true };
                },
                AssetType::EkuboVault => {
                    let (asset0, asset1) = self.custom_assets.read(asset);
                    let (asset0_price, _) = self.pragma_oracle.price(pool_id, asset0);
                    let (asset1_price, _) = self.pragma_oracle.price(pool_id, asset1);
                    let assets = IClVaultDispatcher { contract_address: asset }
                        .convert_to_assets(SCALE);
                    let decimals0 = ERC20Helper::decimals(asset0);
                    let decimals1 = ERC20Helper::decimals(asset1);
                    // todo...change 18 to token decimals
                    let value = ((assets.amount0 * asset0_price) / pow::ten_pow(decimals0.into())) + ((assets.amount1 * asset1_price) / pow::ten_pow(decimals1.into()));
                    return AssetPrice { value, is_valid: true };
                },
                AssetType::None => {
                    // Native Asset
                    let (value, is_valid) = self.pragma_oracle.price(pool_id, asset);
                    return AssetPrice { value, is_valid };
                }
            }
            let (value, is_valid) = self.pragma_oracle.price(pool_id, asset);
            AssetPrice { value, is_valid }
        }


        /// Returns the current interest rate for a given asset in a given pool, given it's utilization
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `utilization` - utilization of the asset
        /// * `last_updated` - last time the interest rate was updated
        /// * `last_full_utilization_rate` - The interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `interest_rate` - current interest rate
        fn interest_rate(
            self: @ContractState,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_full_utilization_rate: u256,
        ) -> u256 {
            let (interest_rate, _) = self
                .interest_rate_model
                .interest_rate(pool_id, asset, utilization, last_updated, last_full_utilization_rate);
            interest_rate
        }

        /// Returns the current rate accumulator for a given asset in a given pool, given it's utilization
        /// # Arguments
        /// * `pool_id` - id of the pool
        /// * `asset` - address of the asset
        /// * `utilization` - utilization of the asset
        /// * `last_updated` - last time the interest rate was updated
        /// * `last_rate_accumulator` - last rate accumulator
        /// * `last_full_utilization_rate` - the interest value when utilization is 100% [SCALE]
        /// # Returns
        /// * `rate_accumulator` - current rate accumulator
        /// * `last_full_utilization_rate` - the interest value when utilization is 100% [SCALE]
        fn rate_accumulator(
            self: @ContractState,
            pool_id: felt252,
            asset: ContractAddress,
            utilization: u256,
            last_updated: u64,
            last_rate_accumulator: u256,
            last_full_utilization_rate: u256,
        ) -> (u256, u256) {
            self
                .interest_rate_model
                .rate_accumulator(
                    pool_id, asset, utilization, last_updated, last_rate_accumulator, last_full_utilization_rate
                )
        }

        /// Modify position callback. Called by the Singleton contract before updating the position.
        /// See `before_modify_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        fn before_modify_position(
            ref self: ContractState,
            context: Context,
            collateral: Amount,
            debt: Amount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (Amount, Amount) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            (collateral, debt)
        }

        /// Modify position callback. Called by the Singleton contract after updating the position.
        /// See `after_modify_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_modify_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self
                .position_hooks
                .after_modify_position(
                    context, collateral_delta, collateral_shares_delta, debt_delta, nominal_debt_delta, data, caller
                )
        }

        /// Transfer position callback. Called by the Singleton contract before transferring collateral / debt
        /// between position.
        // / See `before_transfer_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `from_context` - contextual state of the user (position owner) from which to transfer collateral / debt
        /// * `to_context` - contextual state of the user (position owner) to which to transfer collateral / debt
        /// * `collateral` - amount of collateral to be transferred
        /// * `debt` - amount of debt to be transferred
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be transferred
        /// * `debt` - amount of debt to be transferred
        fn before_transfer_position(
            ref self: ContractState,
            from_context: Context,
            to_context: Context,
            collateral: UnsignedAmount,
            debt: UnsignedAmount,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> (UnsignedAmount, UnsignedAmount) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self.position_hooks.before_transfer_position(from_context, to_context, collateral, debt, data, caller)
        }

        /// Transfer position callback. Called by the Singleton contract after transferring collateral / debt
        /// See `after_transfer_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `from_context` - contextual state of the user (position owner) from which to transfer collateral / debt
        /// * `to_context` - contextual state of the user (position owner) to which to transfer collateral / debt
        /// * `collateral_delta` - collateral balance delta that was transferred
        /// * `collateral_shares_delta` - collateral shares balance delta that was transferred
        /// * `debt_delta` - debt balance delta that was transferred
        /// * `nominal_debt_delta` - nominal debt balance delta that was transferred
        /// * `data` - modify position data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_transfer_position(
            ref self: ContractState,
            from_context: Context,
            to_context: Context,
            collateral_delta: u256,
            collateral_shares_delta: u256,
            debt_delta: u256,
            nominal_debt_delta: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self
                .position_hooks
                .after_transfer_position(
                    from_context,
                    to_context,
                    collateral_delta,
                    collateral_shares_delta,
                    debt_delta,
                    nominal_debt_delta,
                    data,
                    caller
                )
        }

        /// Liquidate position callback. Called by the Singleton contract before liquidating the position.
        /// See `before_liquidate_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral` - amount of collateral to be set/added/removed
        /// * `debt` - amount of debt to be set/added/removed
        /// * `data` - liquidation data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `collateral` - amount of collateral to be removed
        /// * `debt` - amount of debt to be removed
        /// * `bad_debt` - amount of bad debt accrued during the liquidation
        fn before_liquidate_position(
            ref self: ContractState, context: Context, data: Span<felt252>, caller: ContractAddress
        ) -> (u256, u256, u256) {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self.position_hooks.before_liquidate_position(context, data, caller)
        }

        /// Liquidate position callback. Called by the Singleton contract after liquidating the position.
        /// See `before_liquidate_position` in `position_hooks.cairo`.
        /// # Arguments
        /// * `context` - contextual state of the user (position owner)
        /// * `collateral_delta` - collateral balance delta of the position
        /// * `collateral_shares_delta` - collateral shares balance delta of the position
        /// * `debt_delta` - debt balance delta of the position
        /// * `nominal_debt_delta` - nominal debt balance delta of the position
        /// * `bad_debt` - accrued bad debt from the liquidation
        /// * `data` - liquidation data
        /// * `caller` - address of the caller
        /// # Returns
        /// * `bool` - true if the callback was successful
        fn after_liquidate_position(
            ref self: ContractState,
            context: Context,
            collateral_delta: i257,
            collateral_shares_delta: i257,
            debt_delta: i257,
            nominal_debt_delta: i257,
            bad_debt: u256,
            data: Span<felt252>,
            caller: ContractAddress
        ) -> bool {
            assert!(get_caller_address() == self.singleton.read(), "caller-not-singleton");
            self
                .position_hooks
                .after_liquidate_position(
                    context,
                    collateral_delta,
                    collateral_shares_delta,
                    debt_delta,
                    nominal_debt_delta,
                    bad_debt,
                    data,
                    caller
                )
        }
    }
}