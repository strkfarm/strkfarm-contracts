#[cfg(test)]
pub mod test_cl_vault {
    use strkfarm_contracts::strategies::cl_vault::interface::{
        IClVaultDispatcher, IClVaultDispatcherTrait, FeeSettings
    };
    use snforge_std::{
        declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_number_global
    };
    use snforge_std::{DeclareResultTrait};
    use starknet::{ContractAddress, get_contract_address, class_hash::class_hash_const,};
    use strkfarm_contracts::helpers::constants;
    use strkfarm_contracts::strategies::cl_vault::interface::ClSettings;
    use strkfarm_contracts::components::ekuboSwap::{EkuboSwapStruct, ekuboSwapImpl};
    use strkfarm_contracts::helpers::ERC20Helper;
    use strkfarm_contracts::interfaces::IEkuboCore::{
        IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait, Bounds, PoolKey, PositionKey
    };
    use strkfarm_contracts::interfaces::IEkuboPositionsNFT::{
        IEkuboNFTDispatcher, IEkuboNFTDispatcherTrait
    };
    use strkfarm_contracts::interfaces::IEkuboPosition::{IEkuboDispatcher, IEkuboDispatcherTrait};
    use ekubo::interfaces::core::{ICoreDispatcher};
    use strkfarm_contracts::components::ekuboSwap::{IRouterDispatcher};
    use ekubo::types::i129::{i129};
    use starknet::contract_address::contract_address_const;
    use openzeppelin::utils::serde::SerializedAppend;
    use strkfarm_contracts::helpers::pow;
    use strkfarm_contracts::interfaces::ERC4626Strategy::Settings;
    use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, Route};
    use strkfarm_contracts::components::swap::{get_swap_params};
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use strkfarm_contracts::helpers::safe_decimal_math;
    use strkfarm_contracts::tests::utils as test_utils;
    use strkfarm_contracts::components::harvester::reward_shares::{
        IRewardShareDispatcher, IRewardShareDispatcherTrait
    };
    use strkfarm_contracts::interfaces::IEkuboDistributor::{Claim};

    fn get_bounds() -> Bounds {
        let bounds = Bounds {
            lower: i129 { mag: 160000, sign: false, }, upper: i129 { mag: 180000, sign: false, },
        };

        bounds
    }

    fn get_bounds_xstrk() -> Bounds {
        let bounds = Bounds {
            lower: i129 { mag: 16000, sign: false, }, upper: i129 { mag: 16600, sign: false, },
        };

        bounds
    }

    fn get_ekubo_settings() -> EkuboSwapStruct {
        let nostraSettings = EkuboSwapStruct {
            core: ICoreDispatcher { contract_address: constants::EKUBO_CORE() },
            router: IRouterDispatcher { contract_address: constants::EKUBO_ROUTER() }
        };

        nostraSettings
    }

    fn get_eth_wst_route() -> Route {
        let sqrt_limit: felt252 = 0;
        let pool_key = get_pool_key();
        let additional: Array<felt252> = array![
            pool_key.token0.into(), // token0
            pool_key.token1.into(), // token1
            pool_key.fee.into(), // fee
            pool_key.tick_spacing.into(), // tick space
            pool_key.extension.into(), // extension
            sqrt_limit, // sqrt limit
        ];
        Route {
            token_from: constants::ETH_ADDRESS(),
            token_to: constants::WST_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0, // doesnt matter
            additional_swap_params: additional
        }
    }

    fn get_wst_eth_route() -> Route {
        let sqrt_limit: felt252 = 362433397725560428311005821073602714129;
        let pool_key = get_pool_key();
        let additional: Array<felt252> = array![
            pool_key.token0.into(), // token0
            pool_key.token1.into(), // token1
            pool_key.fee.into(), // fee
            pool_key.tick_spacing.into(), // tick space
            pool_key.extension.into(), // extension
            sqrt_limit, // sqrt limit
        ];
        Route {
            token_from: constants::WST_ADDRESS(),
            token_to: constants::ETH_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0, // doesnt matter
            additional_swap_params: additional
        }
    }

    fn get_strk_xstrk_route() -> Route {
        let sqrt_limit: felt252 = 0;

        let additional: Array<felt252> = array![
            constants::XSTRK_ADDRESS().into(), // token0
            constants::STRK_ADDRESS().into(), // token1
            34028236692093847977029636859101184, // fee
            200, // tick space
            0, // extension
            sqrt_limit, // sqrt limit
        ];
        Route {
            token_from: constants::STRK_ADDRESS(),
            token_to: constants::XSTRK_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0, // doesnt matter
            additional_swap_params: additional
        }
    }

    fn get_xstrk_strk_route() -> Route {
        let sqrt_limit: felt252 = 0;

        let additional: Array<felt252> = array![
            constants::XSTRK_ADDRESS().into(), // token0
            constants::STRK_ADDRESS().into(), // token1
            34028236692093847977029636859101184, // fee
            200, // tick space
            0, // extension
            sqrt_limit, // sqrt limit
        ];
        Route {
            token_from: constants::XSTRK_ADDRESS(),
            token_to: constants::STRK_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 0, // doesnt matter
            additional_swap_params: additional
        }
    }

    fn get_harvest_settings() -> Settings {
        let settings = Settings {
            rewardsContract: contract_address_const::<0x00>(),
            lendClassHash: class_hash_const::<0x00>(),
            swapClassHash: class_hash_const::<0x00>()
        };

        settings
    }

    fn get_pool_key_xstrk() -> PoolKey {
        let poolkey = PoolKey {
            token0: constants::XSTRK_ADDRESS(),
            token1: constants::STRK_ADDRESS(),
            fee: 34028236692093847977029636859101184,
            tick_spacing: 200,
            extension: contract_address_const::<0x00>()
        };

        poolkey
    }

    fn get_pool_key() -> PoolKey {
        let poolkey = PoolKey {
            token0: constants::WST_ADDRESS(),
            token1: constants::ETH_ADDRESS(),
            fee: 34028236692093847977029636859101184,
            tick_spacing: 200,
            extension: contract_address_const::<0x00>()
        };

        poolkey
    }

    // fn deploy_avnu() {
    //   let avnu = declare("Exchange").unwrap().contract_class();
    //   let this = get_contract_address();
    //   let mut calldata: Array<felt252> = array![this.into(), this.into()];
    //   let (address, _) = avnu.deploy_at(@calldata,
    //   strkfarm::helpers::constants::AVNU_EX()).expect('Avnu deploy failed');

    //   let ekubo_ch = declare("EkuboAdapter").unwrap().contract_class();
    //   avnu::exchange::IExchangeDispatcher {
    //     contract_address: address
    //   }.set_adapter_class_hash(constants::EKUBO_CORE(), *ekubo_ch.class_hash);
    // }

    fn ekubo_swap(
        route: Route, from_token: ContractAddress, to_token: ContractAddress, from_amount: u256
    ) {
        let ekubo = get_ekubo_settings();
        let mut route_array = ArrayTrait::<Route>::new();
        route_array.append(route);
        let swap_params = get_swap_params(
            from_token: from_token,
            from_amount: from_amount,
            to_token: to_token,
            to_amount: 0,
            to_min_amount: 0,
            routes: route_array
        );
        ekubo.swap(swap_params);
    }

    fn deploy_cl_vault() -> (IClVaultDispatcher, ERC20ABIDispatcher) {
        let accessControl = test_utils::deploy_access_control();
        let clVault = declare("ConcLiquidityVault").unwrap().contract_class();
        let poolkey = get_pool_key();
        let bounds = get_bounds();
        let fee_bps = 1000;
        let name: ByteArray = "uCL_token";
        let symbol: ByteArray = "UCL";
        let mut calldata: Array<felt252> = array![];
        calldata.append_serde(name);
        calldata.append_serde(symbol);
        calldata.append(accessControl.into());
        calldata.append(constants::EKUBO_POSITIONS().into());
        calldata.append_serde(bounds);
        calldata.append_serde(poolkey);
        calldata.append(constants::EKUBO_POSITIONS_NFT().into());
        calldata.append(constants::EKUBO_CORE().into());
        calldata.append(constants::ORACLE_OURS().into());
        let fee_settings = FeeSettings {
            fee_bps: fee_bps, fee_collector: contract_address_const::<0x053c69eDcB1a65A8687Ec7Ad8fC23fD7cc815186fE4380bb6A5bf31df52361FF>()
        };
        fee_settings.serialize(ref calldata);
        let (address, _) = clVault.deploy(@calldata).expect('ClVault deploy failed');

        return (
            IClVaultDispatcher { contract_address: address },
            ERC20ABIDispatcher { contract_address: address },
        );
    }

    fn deploy_cl_vault_xstrk() -> (IClVaultDispatcher, ERC20ABIDispatcher) {
        let accessControl = test_utils::deploy_access_control();
        let clVault = declare("ConcLiquidityVault").unwrap().contract_class();
        let poolkey = get_pool_key_xstrk();
        let bounds = get_bounds_xstrk();
        let strk_xstrk_route = get_strk_xstrk_route();
        let xstrk_strk_route = get_xstrk_strk_route();
        let mut strk_xstrk_routeArray = ArrayTrait::<Route>::new();
        let mut xstrk_strk_routeArray = ArrayTrait::<Route>::new();
        strk_xstrk_routeArray.append(strk_xstrk_route);
        xstrk_strk_routeArray.append(xstrk_strk_route);
        let fee_bps = 1000;
        let name: ByteArray = "uCL_token";
        let symbol: ByteArray = "UCL";
        let mut calldata: Array<felt252> = array![];
        calldata.append_serde(name);
        calldata.append_serde(symbol);
        calldata.append(accessControl.into());
        calldata.append(constants::EKUBO_POSITIONS().into());
        calldata.append_serde(bounds);
        calldata.append_serde(poolkey);
        calldata.append(constants::EKUBO_POSITIONS_NFT().into());
        calldata.append(constants::EKUBO_CORE().into());
        calldata.append(constants::ORACLE_OURS().into());
        let fee_settings = FeeSettings {
            fee_bps: fee_bps, fee_collector: contract_address_const::<0x053c69eDcB1a65A8687Ec7Ad8fC23fD7cc815186fE4380bb6A5bf31df52361FF>()
        };
        fee_settings.serialize(ref calldata);
        let (address, _) = clVault.deploy(@calldata).expect('ClVault deploy failed');

        return (
            IClVaultDispatcher { contract_address: address },
            ERC20ABIDispatcher { contract_address: address },
        );
    }

    fn vault_init(amount: u256) {
        let ekubo_user = constants::EKUBO_USER_ADDRESS();
        let this: ContractAddress = get_contract_address();
        /// println!("vault_init:this: {:?}", this);
        start_cheat_caller_address(constants::ETH_ADDRESS(), ekubo_user);
        ERC20Helper::transfer(constants::ETH_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::ETH_ADDRESS());
        /// println!("amount {:?}", amount);

        start_cheat_caller_address(constants::WST_ADDRESS(), ekubo_user);
        ERC20Helper::transfer(constants::WST_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::WST_ADDRESS());
        /// println!("amount {:?}", amount);
    }

    fn vault_init_xstrk_pool(amount: u256) {
        let ekubo_user = constants::VESU_SINGLETON_ADDRESS();
        let this: ContractAddress = get_contract_address();

        start_cheat_caller_address(constants::STRK_ADDRESS(), ekubo_user);
        ERC20Helper::transfer(constants::STRK_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::STRK_ADDRESS());
        start_cheat_caller_address(constants::XSTRK_ADDRESS(), ekubo_user);
        ERC20Helper::transfer(constants::XSTRK_ADDRESS(), this, amount);
        stop_cheat_caller_address(constants::XSTRK_ADDRESS());
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_clVault_constructer() {
        let (clVault, erc20Disp) = deploy_cl_vault();
        let settings: ClSettings = clVault.get_settings();
        assert(
            settings.ekubo_positions_contract == constants::EKUBO_POSITIONS(),
            'invalid ekubo positions'
        );
        assert(
            settings.ekubo_positions_nft == constants::EKUBO_POSITIONS_NFT(),
            'invalid ekubo positions nft'
        );
        assert(settings.ekubo_core == constants::EKUBO_CORE(), 'invalid ekubo core');
        assert(settings.oracle == constants::ORACLE_OURS(), 'invalid pragma oracle');
        assert(clVault.total_liquidity() == 0, 'invalid total supply');

        assert(erc20Disp.name() == "uCL_token", 'invalid name');
        assert(erc20Disp.symbol() == "UCL", 'invalid symbol');
        assert(erc20Disp.decimals() == 18, 'invalid decimals');
        assert(erc20Disp.total_supply() == 0, 'invalid total supply');
    }

    // PASSED
    #[test]
    #[fork("mainnet_1134787")]
    fn test_ekubo_deposit() {
        let amount = 10 * pow::ten_pow(18);
        let this = get_contract_address();
        /// println!("this: {:?}", this);

        // approve the necessary tokens linked with liquidity to be created
        let (clVault, _) = deploy_cl_vault();
        assert(clVault.get_settings().contract_nft_id == 0, 'nft id not zero on deploy');
        vault_init(amount);
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);
        /// println!("clVault.contract_address: {:?}", clVault.contract_address);

        // deposit once
        let expected_shares1 = clVault.convert_to_shares(amount, amount);
        let shares1 = clVault.deposit(amount, amount, this);
        assert(shares1 > 0, 'invalid shares minted');
        assert(shares1 == expected_shares1, 'invalid shares minted');
        let settings: ClSettings = clVault.get_settings();
        let nft_id: u64 = settings.contract_nft_id;
        let nft_id_u256: u256 = nft_id.into();
        let nft_disp = IEkuboNFTDispatcher { contract_address: settings.ekubo_positions_nft };
        /// println!("nft_id: {:?}", nft_id);

        // assert correct NFT ID, and ensure all balance is used
        assert(nft_disp.ownerOf(nft_id_u256) == clVault.contract_address, 'invalid owner');
        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid ETH amount'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid WST amount'
        );
        /// println!("checked balances");

        // assert for near equal values
        let cl_shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        let total_liquidity: u256 = clVault.get_position().liquidity.into();
        /// println!("cl_shares_bal: {:?}", cl_shares_bal);
        /// println!("total_liquidity: {:?}", total_liquidity);
        assert((cl_shares_bal) == (total_liquidity), 'invalid shares minted');

        // deposit again
        vault_init(amount);
        let expected_shares2 = clVault.convert_to_shares(amount, amount);
        let shares2 = clVault.deposit(amount, amount, this);
        assert(shares2 > 0, 'invalid shares minted');
        assert(shares2 == expected_shares2, 'invalid shares minted');
        let settings: ClSettings = clVault.get_settings();
        assert(nft_id == settings.contract_nft_id, 'nft id not constant');
        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid ETH amount'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid WST amount'
        );

        // assert for near equal values
        let cl_shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        let total_liquidity: u256 = clVault.get_position().liquidity.into();
        /// println!("cl_shares_bal: {:?}", cl_shares_bal);
        /// println!("total_liquidity: {:?}", total_liquidity);
        assert(
            (cl_shares_bal / pow::ten_pow(3)) == (total_liquidity / pow::ten_pow(3)),
            'invalid shares minted'
        );
    }

    //WITHDRAW TESTS
    // PASSED
    #[test]
    #[fork("mainnet_1134787")]
    fn test_ekubo_withdraw() {
        let amount = 10 * pow::ten_pow(18);

        let this = get_contract_address();
        let (clVault, _) = deploy_cl_vault();
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);
        vault_init(amount);

        //deposit
        let shares = clVault.deposit(amount, amount, this);
        assert(shares > 0, 'invalid shares minted');
        let position = clVault.get_position();
        let liquidity_256: u256 = position.liquidity.into();
        let vault_shares = ERC20Helper::balanceOf(clVault.contract_address, this);
        assert(liquidity_256 == vault_shares, 'invalid liquidity');
        assert(shares == vault_shares, 'invalid liquidity');

        let eth_before_withdraw = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
        let wst_before_withdraw = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);

        //withdraw partial
        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
        let withdraw_amount = liquidity_256 / 2;
        clVault.withdraw(withdraw_amount, this);

        let shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        assert(shares_bal == (shares - withdraw_amount), 'invalid shares minted');
        let partial_eth_bal = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
        let partial_wst_bal = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);
        assert(partial_eth_bal > eth_before_withdraw, 'eth not withdrawn');
        assert(partial_wst_bal > wst_before_withdraw, 'wst not withdrawn');
        let liquidity_256_after_withdraw: u256 = clVault.get_position().liquidity.into();
        assert(
            liquidity_256_after_withdraw == (liquidity_256 - withdraw_amount),
            'invalid liquidity removed'
        );
        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );

        //withdraw full
        let shares_left = ERC20Helper::balanceOf(clVault.contract_address, this);
        clVault.withdraw(shares_left, this);
        let liquidity_left = clVault.get_position().liquidity;
        let neg_liq = liquidity_left / 1000;
        assert(neg_liq == 0, 'liquidity not 0');
        assert(clVault.get_settings().contract_nft_id == 0, 'nft id not 0');
        let total_eth_bal = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
        let total_wst_bal = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);
        assert(total_eth_bal > partial_eth_bal, 'total eth not withdrawn');
        assert(total_wst_bal > partial_wst_bal, 'total wst eth not withdrawn');
        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );

        let shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        assert(shares_bal == 0, 'invalid shares minted');
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_handle_fees() {
        let amount = 10 * pow::ten_pow(18);
        vault_init(amount * 2);

        let this = get_contract_address();
        let (clVault, _) = deploy_cl_vault();
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount);

        //deposit
        let _ = clVault.deposit(amount, amount, this);

        // check if function works with 0 fees
        let liquidity_before_fees = clVault.get_position().liquidity;
        clVault.handle_fees();
        let liquidity_after_fees = clVault.get_position().liquidity;
        assert(liquidity_after_fees == liquidity_before_fees, 'invalid liquidity');
        /// println!("first handle fee passed");

        let pool_price_before = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key())
            .tick
            .mag;

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 1000000000000000000
        );
        /// println!("first swap passed");

        let wst_route = get_wst_eth_route();
        ekubo_swap(
            wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 400000000000000000
        );
        /// println!("second swap passed");

        let wst_route = get_wst_eth_route();
        ekubo_swap(
            wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 300000000000000000
        );
        /// println!("third swap passed");

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 100000000000000000
        );
        /// println!("fourth swap passed");

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 200000000000000000
        );
        /// println!("fifth swap passed");

        let pool_price_after = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key())
            .tick
            .mag;

        /// println!("pool price before: {:?}", pool_price_before);
        /// println!("pool price after: {:?}", pool_price_after);
        assert(pool_price_before != pool_price_after, 'invalid swap pool');

        //call handle fees and check how much fees was generated from collect fees
        let liquidity_before_fees = clVault.get_position().liquidity;
        clVault.handle_fees();
        let liquidity_after_fees = clVault.get_position().liquidity;

        assert(liquidity_after_fees > liquidity_before_fees, 'invalid liquidity');
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_ekubo_rebalance() {
        let amount = 10 * pow::ten_pow(18);
        // deploy_avnu();
        vault_init(amount);

        let this = get_contract_address();
        let (clVault, _) = deploy_cl_vault();
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount);

        let _ = clVault.deposit(amount, amount, this);
        let liquidity1 = clVault.get_position().liquidity;
        println!("liquidity before {:?}", liquidity1);
        /// println!("deposit passed");
        let old_bounds = clVault.get_settings().bounds_settings;

        // new bounds
        let new_lower_bound: u128 = 169000;
        let new_upper_bound: u128 = 180000;
        let bounds = Bounds {
            lower: i129 { mag: new_lower_bound, sign: false },
            upper: i129 { mag: new_upper_bound, sign: false }
        };
        /// println!("new bounds ready");

        // rebalance
        /// println!("cl vault: {:?}", clVault.contract_address);
        let mut eth_route = get_eth_wst_route();
        eth_route.percent = 1000000000000;
        let pool_key = get_pool_key();
        let additional: Array<felt252> = array![
            pool_key.token0.into(), // token0
            pool_key.token1.into(), // token1
            pool_key.fee.into(), // fee
            pool_key.tick_spacing.into(), // tick space
            pool_key.extension.into(), // extension
            pow::ten_pow(70).try_into().unwrap(), // sqrt limit
        ];
        eth_route.additional_swap_params = additional;
        let routes: Array<Route> = array![eth_route.clone()];
        let swap_params = AvnuMultiRouteSwap {
            token_from_address: eth_route.clone().token_from,
            // got amont from trail and error
            token_from_amount: 1701 * pow::ten_pow(18) / 1000,
            token_to_address: eth_route.token_to,
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: clVault.contract_address,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: contract_address_const::<0x00>(),
            routes
        };
        /// println!("swap params ready");
        clVault.rebalance(bounds, swap_params);
        /// println!("rebalance passed");
        // assert total usd value is roughly same after rebalance
        let liquidity2 = clVault.get_position().liquidity;
        println!("liquidity after {:?}", liquidity2);
        // assert bounds are updated and current liquidity > 0
        let liquidity_after_rebalance = clVault.get_position().liquidity;
        assert(liquidity_after_rebalance > 0, 'invalid liquidity');
        let bounds = clVault.get_settings().bounds_settings;
        assert(bounds.lower.mag == new_lower_bound, 'invalid bound written');
        assert(bounds.upper.mag == new_upper_bound, 'invalid bound written');

        // assert that old bounds have 0 liquidity
        let position_key = PositionKey {
            salt: clVault.get_settings().contract_nft_id,
            owner: constants::EKUBO_POSITIONS(),
            bounds: old_bounds
        };
        let pos_old_bounds = IEkuboCoreDispatcher { contract_address: constants::EKUBO_CORE() }
            .get_position(clVault.get_settings().pool_key, position_key);
        assert(pos_old_bounds.liquidity == 0, 'Invalid liquidity rebalanced');
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_strk_xstrk_pool() {
        let amount = 500000 * pow::ten_pow(18);
        vault_init_xstrk_pool(amount * 3);

        let this = get_contract_address();
        let (clVault, _) = deploy_cl_vault_xstrk();
        ERC20Helper::approve(constants::STRK_ADDRESS(), clVault.contract_address, amount);
        ERC20Helper::approve(constants::XSTRK_ADDRESS(), clVault.contract_address, amount);

        let _ = clVault.deposit(amount, amount, this);
        let settings: ClSettings = clVault.get_settings();
        let nft_id: u64 = settings.contract_nft_id;
        let nft_id_u256: u256 = nft_id.into();
        let nft_disp = IEkuboNFTDispatcher { contract_address: settings.ekubo_positions_nft };

        // assert correct NFT ID, and ensure all balance is used
        assert(nft_disp.ownerOf(nft_id_u256) == clVault.contract_address, 'invalid owner');
        assert(
            ERC20Helper::balanceOf(constants::STRK_ADDRESS(), clVault.contract_address) == 0,
            'invalid ETH amount'
        );
        assert(
            ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), clVault.contract_address) == 0,
            'invalid WST amount'
        );

        let pool_price_before = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key_xstrk())
            .tick
            .mag;

        let mut x = 1;
        loop {
            x += 1;
            let eth_route = get_strk_xstrk_route();
            ekubo_swap(
                eth_route,
                constants::STRK_ADDRESS(),
                constants::XSTRK_ADDRESS(),
                5000000000000000000000
            );

            let wst_route = get_xstrk_strk_route();
            ekubo_swap(
                wst_route,
                constants::XSTRK_ADDRESS(),
                constants::STRK_ADDRESS(),
                500000000000000000000
            );
            if x == 50 {
                break;
            }
        };

        let pool_price_after = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key_xstrk())
            .tick
            .mag;

        assert(pool_price_before != pool_price_after, 'invalid swap pool');

        //call handle fees and check how much fees was generated from collect fees
        let liquidity_before_fees = clVault.get_position().liquidity;
        clVault.handle_fees();
        let liquidity_after_fees = clVault.get_position().liquidity;

        assert(liquidity_after_fees >= liquidity_before_fees, 'invalid liquidity');

        let strk_before_withdraw = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
        let xstrk_before_withdraw = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
        /// println!("strk bal before withdraw {:?}", strk_before_withdraw);
        /// println!("xstrk bal before withdraw {:?}", xstrk_before_withdraw);

        //withdraw partial
        /// println!("withdraw partial");
        let all_shares = ERC20Helper::balanceOf(clVault.contract_address, this);
        /// println!("all shares {:?}", all_shares);
        let withdraw_amount: u256 = all_shares / 2;
        clVault.withdraw(withdraw_amount, this);

        let partial_strk_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
        let partial_xstrk_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
        /// println!("partial strk bal after withdraw {:?}", partial_strk_bal);
        /// println!("partial xstrk bal after withdraw {:?}", partial_xstrk_bal);
        assert(partial_strk_bal > strk_before_withdraw, 'strk not withdrawn');
        assert(partial_xstrk_bal > xstrk_before_withdraw, 'xstrk not withdrawn');
        let vault_bal0 = ERC20Helper::balanceOf(
            constants::STRK_ADDRESS(), clVault.contract_address
        );
        let vault_bal1 = ERC20Helper::balanceOf(
            constants::XSTRK_ADDRESS(), clVault.contract_address
        );
        /// println!("vault bal0: {:?}", vault_bal0);
        /// println!("vault bal1: {:?}", vault_bal1);
        assert(
            safe_decimal_math::is_under_by_percent_bps(vault_bal0, amount, 1), 'invalid token bal'
        );
        assert(
            safe_decimal_math::is_under_by_percent_bps(vault_bal1, amount, 1), 'invalid token bal'
        );

        //withdraw full
        /// println!("withdraw full");
        let shares_left = ERC20Helper::balanceOf(clVault.contract_address, this);
        clVault.withdraw(shares_left, this);
        let total_strk_bal = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), this);
        let total_xstrk_bal = ERC20Helper::balanceOf(constants::XSTRK_ADDRESS(), this);
        assert(total_strk_bal > partial_strk_bal, 'total eth not withdrawn');
        assert(total_xstrk_bal > partial_xstrk_bal, 'total wst eth not withdrawn');
        let vault_bal0 = ERC20Helper::balanceOf(
            constants::STRK_ADDRESS(), clVault.contract_address
        );
        let vault_bal1 = ERC20Helper::balanceOf(
            constants::XSTRK_ADDRESS(), clVault.contract_address
        );
        /// println!("vault bal0: {:?}", vault_bal0);
        /// println!("vault bal1: {:?}", vault_bal1);
        assert(
            safe_decimal_math::is_under_by_percent_bps(vault_bal0, amount, 1), 'invalid token bal'
        );
        assert(
            safe_decimal_math::is_under_by_percent_bps(vault_bal1, amount, 1), 'invalid token bal'
        );
    }

    #[test]
    #[fork("mainnet_1134787")]
    #[should_panic(expected: ('Access: Missing relayer role',))]
    fn test_rebalance_invalid_permissions() {
        let (clVault, _) = deploy_cl_vault();

        // new bounds
        let new_lower_bound: u128 = 169000;
        let new_upper_bound: u128 = 180000;
        let bounds = Bounds {
            lower: i129 { mag: new_lower_bound, sign: false },
            upper: i129 { mag: new_upper_bound, sign: false }
        };

        let mut eth_route = get_eth_wst_route();
        eth_route.percent = 1000000000000;
        let swap_params = AvnuMultiRouteSwap {
            token_from_address: eth_route.clone().token_from,
            // got amont from trail and error
            token_from_amount: 2744 * pow::ten_pow(18) / 1000,
            token_to_address: eth_route.token_to,
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: clVault.contract_address,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: contract_address_const::<0x00>(),
            routes: array![]
        };
        /// println!("swap params ready");
        start_cheat_caller_address(clVault.contract_address, constants::EKUBO_USER_ADDRESS());
        clVault.rebalance(bounds, swap_params);
        stop_cheat_caller_address(clVault.contract_address);
    }

    #[test]
    #[fork("mainnet_1134787")]
    #[should_panic(expected: ('Access: Missing governor role',))]
    fn test_set_settings_invalid_permissions() {
        let (clVault, _) = deploy_cl_vault();

        start_cheat_caller_address(clVault.contract_address, constants::EKUBO_USER_ADDRESS());
        let fee_settings = FeeSettings {
            fee_bps: 1000, fee_collector: contract_address_const::<0x123>()
        };
        clVault.set_settings(fee_settings);
        stop_cheat_caller_address(clVault.contract_address);
    }


    #[test]
    #[fork("mainnet_1134787")]
    fn test_set_settings_pass() {
        let (clVault, _) = deploy_cl_vault();

        // new bounds
        let fee_settings = FeeSettings {
            fee_bps: 1000, fee_collector: contract_address_const::<0x123>()
        };
        clVault.set_settings(fee_settings);
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_set_incentives_pass() {
        let (clVault, _) = deploy_cl_vault();

        clVault.set_incentives_off();
    }

    #[test]
    #[fork("mainnet_1134787")]
    #[should_panic(expected: ('Access: Missing governor role',))]
    fn test_set_incentives_invalid_permissions() {
        let (clVault, _) = deploy_cl_vault();

        start_cheat_caller_address(clVault.contract_address, constants::EKUBO_USER_ADDRESS());
        clVault.set_incentives_off();
        stop_cheat_caller_address(clVault.contract_address);
    }

    #[test]
    #[fork("mainnet_1134787")]
    #[should_panic(expected: ('invalid swap params [1]',))]
    fn test_handle_ununsed_invalid_from_token() {
        let (clVault, _) = deploy_cl_vault();

        let mut eth_route = get_eth_wst_route();
        eth_route.percent = 1000000000000;
        let swap_params = AvnuMultiRouteSwap {
            token_from_address: constants::STRK_ADDRESS(),
            // got amont from trail and error
            token_from_amount: 2744 * pow::ten_pow(18) / 1000,
            token_to_address: eth_route.token_to,
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: clVault.contract_address,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: contract_address_const::<0x00>(),
            routes: array![]
        };
        /// println!("swap params ready");
        clVault.handle_unused(swap_params);
    }

    #[test]
    #[fork("mainnet_1134787")]
    #[should_panic(expected: ('invalid swap params [2]',))]
    fn test_handle_ununsed_invalid_to_token() {
        let (clVault, _) = deploy_cl_vault();

        let mut eth_route = get_eth_wst_route();
        eth_route.percent = 1000000000000;
        let swap_params = AvnuMultiRouteSwap {
            token_from_address: eth_route.clone().token_from,
            // got amont from trail and error
            token_from_amount: 2744 * pow::ten_pow(18) / 1000,
            token_to_address: constants::STRK_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: clVault.contract_address,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: contract_address_const::<0x00>(),
            routes: array![]
        };
        /// println!("swap params ready");
        clVault.handle_unused(swap_params);
    }

    #[test]
    #[fork("mainnet_1134787")]
    #[should_panic(expected: ('Access: Missing relayer role',))]
    fn test_handle_ununsed_no_auth() {
        let (clVault, _) = deploy_cl_vault();

        let mut eth_route = get_eth_wst_route();
        eth_route.percent = 1000000000000;
        let swap_params = AvnuMultiRouteSwap {
            token_from_address: eth_route.clone().token_from,
            // got amont from trail and error
            token_from_amount: 2744 * pow::ten_pow(18) / 1000,
            token_to_address: constants::STRK_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: clVault.contract_address,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: contract_address_const::<0x00>(),
            routes: array![]
        };

        start_cheat_caller_address(clVault.contract_address, constants::EKUBO_USER_ADDRESS());
        clVault.handle_unused(swap_params);
        stop_cheat_caller_address(clVault.contract_address);
    }

    #[test]
    #[fork("mainnet_1165999")]
    fn test_harvest_cl_vault() {
        let block = 100;
        start_cheat_block_number_global(block);

        let (clVault, _) = deploy_cl_vault();
        let ekubo_defi_spring = test_utils::deploy_defi_spring_ekubo();

        // deposit
        let amount = 10 * pow::ten_pow(18);
        vault_init(amount * 2);
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);
        let shares1 = clVault.deposit(amount, amount, get_contract_address());

        let rsDisp = IRewardShareDispatcher { contract_address: clVault.contract_address };
        let (additional, last_block, pending_round_points) = rsDisp
            .get_additional_shares(get_contract_address());
        assert(additional == 0, 'invalid additional shares');
        assert(last_block == block, 'invalid last block');
        assert(pending_round_points == 0, 'invalid pending round points');

        // deposit again
        let block = block + 100;
        start_cheat_block_number_global(block);
        let shares2 = clVault.deposit(amount, amount, get_contract_address());
        let (additional, last_block, pending_round_points) = rsDisp
            .get_additional_shares(get_contract_address());
        assert(additional == 0, 'invalid additional shares');
        assert(last_block == block, 'invalid last block');
        /// println!("shares1: {:?}", shares1);
        /// println!("shares2: {:?}", shares2);
        /// println!("pending_round_points: {:?}", pending_round_points);
        assert(
            pending_round_points == (shares1 * 100).try_into().unwrap(),
            'invalid pending round points'
        );

        // harvest
        let block = block + 100;
        start_cheat_block_number_global(block);
        let pre_bal_strk = ERC20Helper::balanceOf(
            constants::STRK_ADDRESS(), clVault.contract_address
        );
        let fee_collector = clVault.get_settings().fee_settings.fee_collector;
        let fee_pre = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), fee_collector);
        let claim = Claim {
            id: 0, amount: pow::ten_pow(18).try_into().unwrap(), claimee: clVault.contract_address,
        };
        let post_fee_amount: u128 = claim.amount - (claim.amount / 10);
        let amt0 = 100000 * post_fee_amount.into() / 1383395;
        let amt1 = post_fee_amount.into() - amt0;
        let swap_params1 = STRKWSTAvnuSwapInfo(amt0, clVault.contract_address);
        let swap_params2 = STRKETHAvnuSwapInfo(amt1, clVault.contract_address);
        let proofs: Array<felt252> = array![1];
        let total_shares_pre = ERC20Helper::total_supply(clVault.contract_address);
        /// println!("harvesting");
        clVault
            .harvest(
                ekubo_defi_spring.contract_address, claim, proofs.span(), swap_params1, swap_params2
            );
        let total_shares_post = ERC20Helper::total_supply(clVault.contract_address);
        let post_bal_strk = ERC20Helper::balanceOf(
            constants::STRK_ADDRESS(), clVault.contract_address
        );
        let fee_post = ERC20Helper::balanceOf(constants::STRK_ADDRESS(), fee_collector);

        assert(total_shares_post > total_shares_pre, 'invalid shares minted');
        assert(post_bal_strk == pre_bal_strk, 'strk not harvested');
        assert(fee_post > fee_pre, 'fee not collected');

        let unminted = rsDisp.get_total_unminted_shares();
        let (additional, last_block, pending_round_points) = rsDisp
            .get_additional_shares(get_contract_address());
        /// println!("additional: {:?}", additional);
        /// println!("last_block: {:?}", last_block);
        /// println!("pending_round_points: {:?}", pending_round_points);
        /// println!("unminted: {:?}", unminted);
        assert(additional == unminted, 'invalid additional shares');
        assert(last_block == block, 'invalid last block');
        assert(pending_round_points == 0, 'invalid pending round points');

        let block = block + 100;
        start_cheat_block_number_global(block);
        let (additional, last_block, pending_round_points) = rsDisp
            .get_additional_shares(get_contract_address());
        /// println!("additional: {:?}", additional);
        /// println!("last_block: {:?}", last_block);
        assert(additional == unminted, 'invalid additional shares[2]');
        assert(last_block == block, 'invalid last block');
        let user_shares = ERC20Helper::balanceOf(clVault.contract_address, get_contract_address());
        assert(
            pending_round_points == (user_shares * 100).try_into().unwrap(),
            'invalid pending round points'
        );
        assert(
            user_shares == (shares1 + shares2 + unminted.try_into().unwrap()), 'invalid user shares'
        );

        // 100% withdraw
        /// println!("withdrawing");
        clVault.withdraw(user_shares, get_contract_address());
        /// println!("withdrawn");

        let (additional, last_block, pending_round_points_new) = rsDisp
            .get_additional_shares(get_contract_address());
        assert(additional == 0, 'invalid additional shares[3]');
        assert(last_block == block, 'invalid last block');
        assert(pending_round_points_new == pending_round_points, 'invalid pending round points');

        let liquidity = clVault.get_position().liquidity;
        assert(liquidity == 0, 'invalid liquidity');
        let bal0_vault = ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address);
        let bal1_vault = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address);
        assert(bal0_vault < 1000000000000, 'invalid wst amount');
        assert(bal1_vault < 1000000000000, 'invalid eth amount');
    }

    #[test]
    #[should_panic(expected: ('Access: Missing relayer role',))]
    #[fork("mainnet_1165999")]
    fn test_harvest_cl_vault_no_auth() {
        let block = 100;
        start_cheat_block_number_global(block);

        let (clVault, _) = deploy_cl_vault();
        let ekubo_defi_spring = test_utils::deploy_defi_spring_ekubo();

        let claim = Claim {
            id: 0, amount: pow::ten_pow(18).try_into().unwrap(), claimee: clVault.contract_address,
        };
        let post_fee_amount: u128 = claim.amount - (claim.amount / 10);
        let amt0 = 100000 * post_fee_amount.into() / 1383395;
        let amt1 = post_fee_amount.into() - amt0;
        let swap_params1 = STRKWSTAvnuSwapInfo(amt0, clVault.contract_address);
        let swap_params2 = STRKETHAvnuSwapInfo(amt1, clVault.contract_address);
        let proofs: Array<felt252> = array![1];

        start_cheat_caller_address(clVault.contract_address, constants::EKUBO_USER_ADDRESS());
        clVault
            .harvest(
                ekubo_defi_spring.contract_address, claim, proofs.span(), swap_params1, swap_params2
            );
        stop_cheat_caller_address(clVault.contract_address);
    }

    // additional tests 
    #[test]
    #[fork("mainnet_1134787")]
    fn test_cl_vault_all_functions() {
        let amount = 10 * pow::ten_pow(18);
        vault_init(amount * 2);

        let this = get_contract_address();
        let (clVault, _) = deploy_cl_vault();
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount);

        let expected_shares1 = clVault.convert_to_shares(amount, amount);
        let shares1 = clVault.deposit(amount, amount, this);
        assert(shares1 > 0, 'invalid shares minted');
        assert(shares1 == expected_shares1, 'invalid shares minted');
        let settings: ClSettings = clVault.get_settings();
        let nft_id: u64 = settings.contract_nft_id;
        let nft_id_u256: u256 = nft_id.into();
        let nft_disp = IEkuboNFTDispatcher { contract_address: settings.ekubo_positions_nft };

        assert(nft_disp.ownerOf(nft_id_u256) == clVault.contract_address, 'invalid owner');
        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid ETH amount'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid WST amount'
        );

        let cl_shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        let total_liquidity: u256 = clVault.get_position().liquidity.into();
        assert((cl_shares_bal) == (total_liquidity), 'invalid shares minted');

        println!("***********************************************************");
        println!("DEPOSIT DONE");
        println!("***********************************************************");

        let old_bounds = clVault.get_settings().bounds_settings;
        let new_lower_bound: u128 = 169000;
        let new_upper_bound: u128 = 180000;
        let bounds = Bounds {
            lower: i129 { mag: new_lower_bound, sign: false },
            upper: i129 { mag: new_upper_bound, sign: false }
        };
        let mut eth_route = get_eth_wst_route();
        eth_route.percent = 1000000000000;
        let pool_key = get_pool_key();
        let additional: Array<felt252> = array![
            pool_key.token0.into(), // token0
            pool_key.token1.into(), // token1
            pool_key.fee.into(), // fee
            pool_key.tick_spacing.into(), // tick space
            pool_key.extension.into(), // extension
            pow::ten_pow(70).try_into().unwrap(), // sqrt limit
        ];
        eth_route.additional_swap_params = additional;
        let routes: Array<Route> = array![eth_route.clone()];
        let swap_params = AvnuMultiRouteSwap {
            token_from_address: eth_route.clone().token_from,
            token_from_amount: 1701 * pow::ten_pow(18) / 1000,
            token_to_address: eth_route.token_to,
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: clVault.contract_address,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: contract_address_const::<0x00>(),
            routes
        };
        clVault.rebalance(bounds, swap_params);
        let liquidity_after_rebalance = clVault.get_position().liquidity;
        assert(liquidity_after_rebalance > 0, 'invalid liquidity');
        let bounds = clVault.get_settings().bounds_settings;
        assert(bounds.lower.mag == new_lower_bound, 'invalid bound written');
        assert(bounds.upper.mag == new_upper_bound, 'invalid bound written');

        // assert that old bounds have 0 liquidity
        let position_key = PositionKey {
            salt: clVault.get_settings().contract_nft_id,
            owner: constants::EKUBO_POSITIONS(),
            bounds: old_bounds
        };
        let pos_old_bounds = IEkuboCoreDispatcher { contract_address: constants::EKUBO_CORE() }
            .get_position(clVault.get_settings().pool_key, position_key);
        assert(pos_old_bounds.liquidity == 0, 'Invalid liquidity rebalanced');

        println!("***********************************************************");
        println!("REBALANCE DONE");
        println!("***********************************************************");

        // handle fees
        let liquidity_before_fees = clVault.get_position().liquidity;
        clVault.handle_fees();
        let liquidity_after_fees = clVault.get_position().liquidity;
        assert(liquidity_after_fees == liquidity_before_fees, 'invalid liquidity');

        let pool_price_before = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key())
            .tick
            .mag;

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 1000000000000000000
        );

        let wst_route = get_wst_eth_route();
        ekubo_swap(
            wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 400000000000000000
        );

        let wst_route = get_wst_eth_route();
        ekubo_swap(
            wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 300000000000000000
        );

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 100000000000000000
        );

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 200000000000000000
        );

        let pool_price_after = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key())
            .tick
            .mag;
        assert(pool_price_before != pool_price_after, 'invalid swap pool');

        //call handle fees and check how much fees was generated from collect fees
        let liquidity_before_fees = clVault.get_position().liquidity;
        clVault.handle_fees();
        let liquidity_after_fees = clVault.get_position().liquidity;

        assert(liquidity_after_fees > liquidity_before_fees, 'invalid liquidity');

        println!("***********************************************************");
        println!("HANDLE FEES DONE");
        println!("***********************************************************");

        //withdraw
        let eth_before_withdraw = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
        let wst_before_withdraw = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);

        let withdraw_amount = 10 * pow::ten_pow(18);
        clVault.withdraw(withdraw_amount, this);

        let shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        assert(shares_bal == (shares1 - withdraw_amount), 'invalid shares minted');
        let partial_eth_bal = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), this);
        let partial_wst_bal = ERC20Helper::balanceOf(constants::WST_ADDRESS(), this);
        assert(partial_eth_bal > eth_before_withdraw, 'eth not withdrawn');
        assert(partial_wst_bal > wst_before_withdraw, 'wst not withdrawn');

        println!("***********************************************************");
        println!("WITHDRAW DONE");
        println!("***********************************************************");
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_ekubo_withdraw_entire_liquidity() {
        let amount = 10 * pow::ten_pow(18);
        let this = get_contract_address();
    
        let (clVault, _) = deploy_cl_vault();
        assert(clVault.get_settings().contract_nft_id == 0, 'nft id not zero on deploy');
        vault_init(amount);
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);

        let shares1 = clVault.deposit(amount, amount, this);

        // withdraw entire liquidity
        clVault.withdraw(shares1, this);

        let liquidity_left = clVault.get_position().liquidity;
        let neg_liq = liquidity_left / 1000;
        assert(neg_liq == 0, 'liquidity not 0');

        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );

        let shares_bal = ERC20Helper::balanceOf(clVault.contract_address, this);
        assert(shares_bal == 0, 'invalid shares minted');

        // test next deposit 
        let amount = 10 * pow::ten_pow(18);
        let this = get_contract_address();
    
        let (clVault, _) = deploy_cl_vault();
        assert(clVault.get_settings().contract_nft_id == 0, 'nft id not zero on deploy');
        vault_init(amount);
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);

        let _ = clVault.deposit(amount, amount, this);
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_ekubo_low_liquidity() {
        let amount = 10 * pow::ten_pow(18);
        let this = get_contract_address();
    
        let (clVault, _) = deploy_cl_vault();
        assert(clVault.get_settings().contract_nft_id == 0, 'nft id not zero on deploy');
        vault_init(amount);
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount * 2);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount * 2);

        let deposit_amount = 1;
        let shares1 = clVault.deposit(deposit_amount, deposit_amount, this);

        clVault.withdraw(shares1, this);

        let liquidity_left = clVault.get_position().liquidity;
        println!("liquidity after withdraw {:?}", liquidity_left);
        // let neg_liq = liquidity_left / 1000;
        assert(liquidity_left == 0, 'liquidity not 0');

        assert(
            ERC20Helper::balanceOf(constants::ETH_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
        assert(
            ERC20Helper::balanceOf(constants::WST_ADDRESS(), clVault.contract_address) == 0,
            'invalid token bal'
        );
    }

    #[test]
    #[fork("mainnet_1134787")]
    fn test_ekubo_fee_ranges() {
        let amount = 10 * pow::ten_pow(18);
        vault_init(amount * 2);

        let this = get_contract_address();
        let (clVault, _) = deploy_cl_vault();
        ERC20Helper::approve(constants::ETH_ADDRESS(), clVault.contract_address, amount);
        ERC20Helper::approve(constants::WST_ADDRESS(), clVault.contract_address, amount);

        let _ = clVault.deposit(amount, amount, this);

        let pool_price_before = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key())
            .tick
            .mag;

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 1000000000000000000
        );

        let wst_route = get_wst_eth_route();
        ekubo_swap(
            wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 400000000000000000
        );

        let wst_route = get_wst_eth_route();
        ekubo_swap(
            wst_route, constants::WST_ADDRESS(), constants::ETH_ADDRESS(), 300000000000000000
        );

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 100000000000000000
        );

        let eth_route = get_eth_wst_route();
        ekubo_swap(
            eth_route, constants::ETH_ADDRESS(), constants::WST_ADDRESS(), 200000000000000000
        );

        let pool_price_after = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_pool_price(get_pool_key())
            .tick
            .mag;

        assert(pool_price_before != pool_price_after, 'invalid swap pool');

        let fee_collector = clVault.get_settings().fee_settings.fee_collector;
        let token0_bal_before = ERC20Helper::balanceOf(constants::WST_ADDRESS(), fee_collector);
        let token1_bal_before = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), fee_collector);
        let settings = clVault.get_settings();
        let token_info = IEkuboDispatcher { contract_address: constants::EKUBO_POSITIONS() }
            .get_token_info(settings.contract_nft_id, settings.pool_key, settings.bounds_settings);
        let fee0 = token_info.fees0;
        let fee1 = token_info.fees1;
        clVault.handle_fees();
        let token0_bal_after = ERC20Helper::balanceOf(constants::WST_ADDRESS(), fee_collector);
        let token1_bal_after = ERC20Helper::balanceOf(constants::ETH_ADDRESS(), fee_collector);

        let fee0_strat = (fee0.into() * settings.fee_settings.fee_bps) / 10000;
        let fee1_strat = (fee1.into() * settings.fee_settings.fee_bps) / 10000;

        let fee0_collector = token0_bal_after - token0_bal_before;
        let fee1_collector = token1_bal_after - token1_bal_before;

        assert(fee0_strat == fee0_collector, 'invalid fee0 transfered');
        assert(fee1_strat == fee1_collector, 'invalid fee1 transfered');
    }

    fn STRKETHAvnuSwapInfo(amount: u256, beneficiary: ContractAddress) -> AvnuMultiRouteSwap {
        let additional1: Array<felt252> = array![
            constants::STRK_ADDRESS().into(),
            constants::ETH_ADDRESS().into(),
            34028236692093847977029636859101184,
            200,
            0,
            10000000000000000000000000000000000000000000000000000000000000000000000
        ];
        let route = Route {
            token_from: constants::STRK_ADDRESS(),
            token_to: constants::ETH_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 1000000000000,
            additional_swap_params: additional1.clone(),
        };
        let routes: Array<Route> = array![route];
        let admin = get_contract_address();
        AvnuMultiRouteSwap {
            token_from_address: constants::STRK_ADDRESS(),
            token_from_amount: amount, // claim amount
            token_to_address: constants::ETH_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: beneficiary,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: admin,
            routes
        }
    }

    fn STRKWSTAvnuSwapInfo(amount: u256, beneficiary: ContractAddress) -> AvnuMultiRouteSwap {
        let additional1: Array<felt252> = array![
            constants::STRK_ADDRESS().into(),
            constants::ETH_ADDRESS().into(),
            34028236692093847977029636859101184,
            200,
            0,
            10000000000000000000000000000000000000000000000000000000000000000000000
        ];

        let additional2: Array<felt252> = array![
            constants::WST_ADDRESS().into(),
            constants::ETH_ADDRESS().into(),
            34028236692093847977029636859101184,
            200,
            0,
            10000000000000000000000000000000000000000000000000000000000000000000000
        ];
        let route = Route {
            token_from: constants::STRK_ADDRESS(),
            token_to: constants::ETH_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 1000000000000,
            additional_swap_params: additional1.clone(),
        };
        let route2 = Route {
            token_from: constants::ETH_ADDRESS(),
            token_to: constants::WST_ADDRESS(),
            exchange_address: constants::EKUBO_CORE(),
            percent: 1000000000000,
            additional_swap_params: additional2,
        };
        let routes: Array<Route> = array![route, route2];
        let admin = get_contract_address();
        AvnuMultiRouteSwap {
            token_from_address: constants::STRK_ADDRESS(),
            token_from_amount: amount, // claim amount
            token_to_address: constants::WST_ADDRESS(),
            token_to_amount: 0,
            token_to_min_amount: 0,
            beneficiary: beneficiary,
            integrator_fee_amount_bps: 0,
            integrator_fee_recipient: admin,
            routes
        }
    }
}
