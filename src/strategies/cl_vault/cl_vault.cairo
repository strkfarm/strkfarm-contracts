#[starknet::contract]
mod ConcLiquidityVault {
    use core::option::OptionTrait;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use openzeppelin::security::pausable::{PausableComponent};
    use openzeppelin::security::reentrancyguard::{ReentrancyGuardComponent};
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use ekubo::types::pool_price::PoolPrice;
    use ekubo::types::position::Position;
    use ekubo::interfaces::mathlib::{IMathLibDispatcherTrait, dispatcher as ekuboLibDispatcher};
    use ekubo::types::i129::i129;
    use starknet::{
        ContractAddress, contract_address_const, get_contract_address, get_caller_address,
        get_block_number
    };
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{ERC20Component,};
    use strkfarm_contracts::components::harvester::reward_shares::{
        RewardShareComponent, IRewardShare
    };
    use strkfarm_contracts::components::harvester::reward_shares::RewardShareComponent::{
        InternalTrait as RewardShareInternalImpl
    };
    use strkfarm_contracts::components::harvester::harvester_lib::{
        HarvestConfig, HarvestConfigImpl, HarvestHooksTrait
    };
    use strkfarm_contracts::components::common::CommonComp;
    use strkfarm_contracts::components::harvester::defi_spring_default_style::{
        SNFStyleClaimSettings, ClaimImpl as DefaultClaimImpl
    };
    use strkfarm_contracts::components::harvester::harvester_lib::HarvestBeforeHookResult;
    use strkfarm_contracts::helpers::ERC20Helper;
    use strkfarm_contracts::interfaces::oracle::{IPriceOracleDispatcher};
    use strkfarm_contracts::interfaces::IEkuboPosition::{IEkuboDispatcher, IEkuboDispatcherTrait};
    use strkfarm_contracts::interfaces::IEkuboPositionsNFT::{
        IEkuboNFTDispatcher, IEkuboNFTDispatcherTrait
    };
    use strkfarm_contracts::interfaces::IEkuboCore::{
        IEkuboCoreDispatcher, IEkuboCoreDispatcherTrait, Bounds, PoolKey, PositionKey
    };
    use strkfarm_contracts::components::swap::{AvnuMultiRouteSwap, AvnuMultiRouteSwapImpl};
    use strkfarm_contracts::interfaces::IEkuboDistributor::Claim;
    use strkfarm_contracts::components::harvester::defi_spring_ekubo_style::{
        EkuboStyleClaimSettings, ClaimImpl
    };
    use strkfarm_contracts::strategies::cl_vault::interface::{
        IClVault, FeeSettings, MyPosition, ClSettings
    };
    use strkfarm_contracts::helpers::safe_decimal_math;
    use strkfarm_contracts::helpers::constants;
    use core::num::traits::Zero;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ReentrancyGuardComponent, storage: reng, event: ReentrancyGuardEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: CommonComp, storage: common, event: CommonCompEvent);
    component!(path: RewardShareComponent, storage: reward_share, event: RewardShareEvent);
    use openzeppelin::token::erc20::interface::IERC20Mixin;

    #[abi(embed_v0)]
    impl RewardShareImpl = RewardShareComponent::RewardShareImpl<ContractState>;
    impl RewardShare = RewardShareComponent::InternalImpl<ContractState>;
    impl RewardSharePrivateImpl = RewardShareComponent::PrivateImpl<ContractState>;

    #[abi(embed_v0)]
    impl CommonCompImpl = CommonComp::CommonImpl<ContractState>;
    impl CommonInternalImpl = CommonComp::InternalImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;


    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        sender: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        sender: ContractAddress,
        #[key]
        receiver: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        reng: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        common: CommonComp::Storage,
        #[substorage(v0)]
        reward_share: RewardShareComponent::Storage,
        // constants
        ekubo_positions_contract: IEkuboDispatcher,
        pool_key: PoolKey,
        ekubo_positions_nft: ContractAddress,
        ekubo_core: ContractAddress,
        oracle: ContractAddress,
        // Changeable settings
        bounds_settings: Bounds,
        fee_settings: FeeSettings,
        // contract managed state
        contract_nft_id: u64,
        sqrt_lower: u256,
        sqrt_upper: u256,
        is_incentives_on: bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        CommonCompEvent: CommonComp::Event,
        #[flat]
        RewardShareEvent: RewardShareComponent::Event,
        Deposit: Deposit,
        Withdraw: Withdraw,
        Rebalance: Rebalance,
        HandleFees: HandleFees,
        FeeSettings: FeeSettings,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Rebalance {
        old_bounds: Bounds,
        old_liquidity: u256,
        new_bounds: Bounds,
        new_liquidity: u256
    }

    #[derive(Drop, starknet::Event)]
    pub struct HandleFees {
        token0_addr: ContractAddress,
        token0_origin_bal: u256,
        token0_deposited: u256,
        token1_addr: ContractAddress,
        token1_origin_bal: u256,
        token1_deposited: u256
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        access_control: ContractAddress,
        ekubo_positions_contract: ContractAddress,
        bounds_settings: Bounds,
        pool_key: PoolKey,
        ekubo_positions_nft: ContractAddress,
        ekubo_core: ContractAddress,
        oracle: ContractAddress,
        fee_settings: FeeSettings,
    ) {
        self.erc20.initializer(name, symbol);
        self.common.initializer(access_control);
        self
            .ekubo_positions_contract
            .write(IEkuboDispatcher { contract_address: ekubo_positions_contract });
        self.set_sqrt_lower_upper(bounds_settings);
        self.pool_key.write(pool_key);
        self.ekubo_positions_nft.write(ekubo_positions_nft);
        self.ekubo_core.write(ekubo_core);
        self.oracle.write(oracle);
        self.fee_settings.write(fee_settings);
        self.is_incentives_on.write(true);
        self.reward_share.init(get_block_number());
    }

    #[abi(embed_v0)]
    impl ExternalImpl of IClVault<ContractState> {
        /// @notice Deposits assets into the contract and mints corresponding shares.
        /// @dev This function handles fees, calculates liquidity, mints shares,
        /// and deposits assets into Ekubo. It ensures that the deposited liquidity
        /// matches the expected amount.
        /// @param amount0 The amount of the first asset to deposit.
        /// @param amount1 The amount of the second asset to deposit.
        /// @param receiver The address that will receive the minted shares.
        /// @return shares The number of shares minted for the deposited liquidity.
        fn deposit(
            ref self: ContractState, amount0: u256, amount1: u256, receiver: ContractAddress
        ) -> u256 {
            self.common.assert_not_paused();
            let caller: ContractAddress = get_caller_address();
            assert(amount0 > 0 || amount1 > 0, 'amounts cannot be zero');

            self.handle_fees();

            // mint shares
            let liquidity = self._max_liquidity(amount0, amount1);
            let shares = self._convert_to_shares(liquidity.into());
            self.erc20.mint(receiver, shares);

            // deposit
            let liquidity_actual = self._ekubo_deposit(caller, amount0, amount1, caller);
            assert(liquidity == liquidity_actual, 'invalid liquidity added');

            self
                .emit(
                    Deposit { sender: caller, owner: receiver, assets: liquidity_actual, shares }
                );
            return shares;
        }

        /// @notice Withdraws assets by redeeming shares from the contract.
        /// @dev This function ensures the caller has enough shares, calculates the assets to
        /// withdraw, handles fees, removes liquidity from the pool, transfers the withdrawn assets
        /// to the receiver, burns the shares, and updates the contract state accordingly.
        /// @param shares The number of shares to redeem.
        /// @param receiver The address that will receive the withdrawn assets.
        /// @return position A struct containing the withdrawn liquidity, amount0, and amount1.
        fn withdraw(
            ref self: ContractState, shares: u256, receiver: ContractAddress
        ) -> MyPosition {
            self.common.assert_not_paused();
            let caller = get_caller_address();

            let max_shares = self.balance_of(caller);
            assert(shares <= max_shares, 'insufficient shares');

            let userPosition = self.convert_to_assets(shares);
            assert(userPosition.liquidity > 0, 'invalid liquidity removed');

            self.handle_fees();

            let pool_key = self.pool_key.read();
            let old_liq = self.get_position().liquidity;

            // withdraw
            let (amt0, amt1) = self._withdraw_position(userPosition.liquidity.try_into().unwrap());

            // burn shares
            self.erc20.burn(caller, shares);

            // transfer proceeds to receiver
            ERC20Helper::transfer(pool_key.token0, receiver, amt0.into());
            ERC20Helper::transfer(pool_key.token1, receiver, amt1.into());

            let current_liq = self.get_position().liquidity;
            if (current_liq == 0) {
                self.contract_nft_id.write(0);
            }
            assert(
                (old_liq - current_liq).into() == userPosition.liquidity,
                'invalid liquidity removed'
            );

            self
                .emit(
                    Withdraw {
                        sender: caller,
                        receiver,
                        owner: receiver,
                        assets: userPosition.liquidity,
                        shares
                    }
                );
            return MyPosition {
                liquidity: userPosition.liquidity, amount0: amt0.into(), amount1: amt1.into()
            };
        }

        /// @notice Converts given asset amounts into the corresponding number of shares.
        /// @dev This function calculates the maximum liquidity based on the provided asset amounts
        ///      and then converts that liquidity into shares.
        /// @param amount0 The amount of the first asset.
        /// @param amount1 The amount of the second asset.
        /// @return shares The number of shares corresponding to the provided asset amounts.
        fn convert_to_shares(self: @ContractState, amount0: u256, amount1: u256) -> u256 {
            let liquidity = self._max_liquidity(amount0, amount1);
            return self._convert_to_shares(liquidity.into());
        }

        /// @notice Converts shares into the corresponding asset amounts.
        /// @dev This function calculates the equivalent liquidity for the given shares,
        ///      converts it to asset amounts using the current pool price, and ensures
        ///      the calculated amounts are valid.
        /// @param shares The number of shares to convert.
        /// @return position A struct containing the corresponding liquidity, amount0, and amount1.
        fn convert_to_assets(self: @ContractState, shares: u256) -> MyPosition {
            let current_sqrt_price = self.get_pool_price().sqrt_ratio;
            let liquidity = self._convert_to_assets(shares);
            let delta = ekuboLibDispatcher()
                .liquidity_delta_to_amount_delta(
                    current_sqrt_price,
                    i129 { mag: liquidity.try_into().unwrap(), sign: false },
                    self.sqrt_lower.read(),
                    self.sqrt_upper.read()
                );
            assert(delta.amount0.sign == false, 'invalid amount0');
            assert(delta.amount1.sign == false, 'invalid amount1');
            return MyPosition {
                liquidity, amount0: delta.amount0.mag.into(), amount1: delta.amount1.mag.into()
            };
        }

        /// @notice Returns the total liquidity of the contract.
        /// @dev This function retrieves the current position and returns its liquidity value.
        /// @return liquidity The total liquidity in the contract.
        fn total_liquidity(self: @ContractState) -> u256 {
            let position = self.get_position();
            position.liquidity.into()
        }

        /// @notice Collects and handles fees generated by the contract.
        /// @dev This function retrieves token balances, collects strategy fees, deposits
        /// collected fees back into the liquidity pool, and emits a fee-handling event.
        fn handle_fees(ref self: ContractState) {
            self.common.assert_not_paused();
            let this: ContractAddress = get_contract_address();
            let poolInfo = self.pool_key.read();
            let token0: ContractAddress = poolInfo.token0;
            let token1: ContractAddress = poolInfo.token1;

            let nft_id = self.contract_nft_id.read();
            let bounds = self.bounds_settings.read();
            let positions_disp = self.ekubo_positions_contract.read();
            let token_info = positions_disp.get_token_info(nft_id, poolInfo, bounds);

            let (fee0, fee1) = self._collect_strat_fee();

            if (fee0 == 0 && fee1 == 0) {
                return;
            }

            // deposit fees
            // @dev This action may leave some unused balances in the contract
            // Adjusting these amounts to exact required amounts unnecessarily
            // overcomplicates the logic and not of significant benefit
            // - This is taken care during rebalance/handle_unused calls
            // which we plan to run at regular intervals
            // (every fews days once or dependening on the amount of fee)
            self._ekubo_deposit(this, fee0, fee1, this);

            self
                .emit(
                    HandleFees {
                        token0_addr: token0,
                        token0_origin_bal: token_info.amount0.into(),
                        token0_deposited: token_info.fees0.into(),
                        token1_addr: token1,
                        token1_origin_bal: token_info.amount1.into(),
                        token1_deposited: token_info.fees1.into()
                    }
                );
        }

        /// @notice Harvests rewards from the specified rewards contract.
        /// @dev This function claims rewards using the provided claim data and proof,
        /// then swaps them based on the given swap information.
        /// @param rewardsContract The contract address from which rewards are claimed.
        /// @param claim The claim data for the rewards.
        /// @param proof The Merkle proof verifying the claim.
        /// @param swapInfo The swap information for converting harvested rewards.
        fn harvest(
            ref self: ContractState,
            rewardsContract: ContractAddress,
            claim: Claim,
            proof: Span<felt252>,
            swapInfo1: AvnuMultiRouteSwap,
            swapInfo2: AvnuMultiRouteSwap
        ) {
            self.common.assert_not_paused();
            assert(self.is_incentives_on.read(), 'incentives are off');
            self.common.assert_relayer_role();

            let ekuboSettings = EkuboStyleClaimSettings { rewardsContract: rewardsContract, };
            let config = HarvestConfig {};
            // just dummy config, not used
            let snfSettings = SNFStyleClaimSettings {
                rewardsContract: contract_address_const::<0>()
            };

            let rewardToken = constants::STRK_ADDRESS();
            let pre_bal = ERC20Helper::balanceOf(rewardToken, get_contract_address());
            config
                .simple_harvest(
                    ref self,
                    ekuboSettings,
                    claim,
                    proof,
                    snfSettings,
                    swapInfo1.clone(), // doesnt do anything anyways
                    IPriceOracleDispatcher { contract_address: self.oracle.read() }
                );
            let post_bal = ERC20Helper::balanceOf(rewardToken, get_contract_address());

            // validate swap info
            // aim to swap 100% of STRK into token0 and token1
            let token0 = self.pool_key.read().token0;
            let token1 = self.pool_key.read().token1;
            assert(
                swapInfo1.token_from_address == constants::STRK_ADDRESS(),
                'invalid token from address [1]'
            );
            assert(swapInfo1.token_to_address == token0, 'invalid token to address [1]');
            assert(
                swapInfo2.token_from_address == constants::STRK_ADDRESS(),
                'invalid token from address [2]'
            );
            assert(swapInfo2.token_to_address == token1, 'invalid token to address [2]');
            let strk_amt = post_bal - pre_bal;
            assert(strk_amt > 0, 'No harvest amt');
            assert(
                swapInfo1.token_from_amount + swapInfo2.token_from_amount == strk_amt,
                'invalid STRK balance'
            );

            let mut token0_amt: u256 = swapInfo1.token_from_amount;
            if (swapInfo1.token_from_amount > 0
                && swapInfo1.token_from_address != swapInfo1.token_to_address) {
                token0_amt = swapInfo1
                    .swap(IPriceOracleDispatcher { contract_address: self.oracle.read() });
            }
            let mut token1_amt: u256 = swapInfo2.token_from_amount;
            if (swapInfo2.token_from_amount > 0
                && swapInfo2.token_from_address != swapInfo2.token_to_address) {
                token1_amt = swapInfo2
                    .swap(IPriceOracleDispatcher { contract_address: self.oracle.read() });
            }

            let bal0_pre = ERC20Helper::balanceOf(token0, get_contract_address());
            let bal1_pre = ERC20Helper::balanceOf(token1, get_contract_address());
            let expected_liquidity = self._max_liquidity(token0_amt, token1_amt);
            let shares = self._convert_to_shares(expected_liquidity.into());
            let new_liquidity = self
                ._ekubo_deposit(
                    get_contract_address(), token0_amt, token1_amt, get_contract_address()
                );
            assert(new_liquidity == expected_liquidity, 'invalid liquidity added');
            let bal0_post = ERC20Helper::balanceOf(token0, get_contract_address());
            let bal1_post = ERC20Helper::balanceOf(token1, get_contract_address());
            let diff0 = token0_amt - (bal0_pre - bal0_post);
            let diff1 = token1_amt - (bal1_pre - bal1_post);
            assert(
                safe_decimal_math::is_under_by_percent_bps(diff0, token0_amt, 1),
                'invalid token0 amount'
            );
            assert(
                safe_decimal_math::is_under_by_percent_bps(diff1, token1_amt, 1),
                'invalid token1 amount'
            );

            let all_shares = self.total_supply();
            self
                .reward_share
                .update_harvesting_rewards(
                    new_liquidity.try_into().unwrap(),
                    shares.try_into().unwrap(),
                    all_shares.try_into().unwrap()
                );
        }

        /// @notice Retrieves the position key associated with the contract.
        /// @dev This function constructs and returns a `PositionKey` using the contract's
        /// NFT ID, owner address, and bounds settings.
        /// @return position_key The position key containing salt, owner, and bounds.
        fn get_position_key(self: @ContractState) -> PositionKey {
            let position_key = PositionKey {
                salt: self.contract_nft_id.read(),
                owner: self.ekubo_positions_contract.read().contract_address,
                bounds: self.bounds_settings.read()
            };

            position_key
        }

        /// @notice Retrieves the current position details from the Ekubo core contract.
        /// @dev This function fetches the position data using the contract's position key
        /// and pool key from the Ekubo core contract.
        /// @return curr_position The current position details.
        fn get_position(self: @ContractState) -> Position {
            let position_key: PositionKey = self.get_position_key();
            let curr_position: Position = IEkuboCoreDispatcher {
                contract_address: self.ekubo_core.read()
            }
                .get_position(self.pool_key.read(), position_key);

            curr_position
        }

        /// @notice Retrieves the current settings of the contract.
        /// @dev This function reads various contract settings including fee settings, bounds, pool
        /// key, and oracle.
        /// @return ClSettings Struct containing the contract's current settings.
        fn get_settings(self: @ContractState) -> ClSettings {
            ClSettings {
                ekubo_positions_contract: self.ekubo_positions_contract.read().contract_address,
                bounds_settings: self.bounds_settings.read(),
                pool_key: self.pool_key.read(),
                ekubo_positions_nft: self.ekubo_positions_nft.read(),
                contract_nft_id: self.contract_nft_id.read(),
                ekubo_core: self.ekubo_core.read(),
                oracle: self.oracle.read(),
                fee_settings: self.fee_settings.read()
            }
        }

        /// @notice Updates the fee settings of the contract.
        /// @dev Only the contract owner can call this function to modify fee settings.
        /// @param fee_settings The new fee settings to be applied.
        fn set_settings(ref self: ContractState, fee_settings: FeeSettings) {
            self.common.assert_governor_role();
            self.fee_settings.write(fee_settings);
            self.emit(fee_settings);
        }

        fn set_incentives_off(ref self: ContractState) {
            self.common.assert_governor_role();
            self.is_incentives_on.write(false);
        }

        /// @notice Rebalances the liquidity position based on new bounds.
        /// @dev This function withdraws existing liquidity, adjusts token balances via swaps,
        ///      updates the position bounds, and redeposits liquidity.
        /// @param new_bounds The new lower and upper tick bounds for the position.
        /// @param swap_params Parameters for swapping tokens to balance liquidity before redeposit.
        fn rebalance(ref self: ContractState, new_bounds: Bounds, swap_params: AvnuMultiRouteSwap) {
            self.common.assert_relayer_role();
            let tick_curr = self.get_pool_price().tick;
            assert(new_bounds.lower <= tick_curr, 'invalid lower bound');
            assert(new_bounds.upper >= tick_curr, 'invalid upper bound');
            self._collect_strat_fee();

            // Withdraw liquidity
            let old_bounds = self.bounds_settings.read();
            let old_position = self.get_position();
            self._withdraw_position(old_position.liquidity.into());
            assert(self.get_position().liquidity == 0, 'invalid liquidity');

            // Update bounds
            self.set_sqrt_lower_upper(new_bounds);

            // Handle unused balances and deposit
            self.handle_unused(swap_params);
            let new_position = self.get_position();

            self
                .emit(
                    Rebalance {
                        old_bounds,
                        old_liquidity: old_position.liquidity.into(),
                        new_bounds,
                        new_liquidity: new_position.liquidity.into()
                    }
                );
        }

        /// @notice Handles any unused token balances by swapping them before redepositing
        /// liquidity.
        /// @dev This function ensures that the majority of token balances are used efficiently
        /// before deposit.
        /// @param swap_params Parameters for swapping tokens to balance liquidity before redeposit.
        fn handle_unused(ref self: ContractState, swap_params: AvnuMultiRouteSwap) {
            self.common.assert_relayer_role();
            let this = get_contract_address();
            let pool_key = self.pool_key.read();
            assert(
                swap_params.token_from_address == pool_key.token0
                    || swap_params.token_from_address == pool_key.token1,
                'invalid swap params [1]'
            );
            assert(
                swap_params.token_to_address == pool_key.token0
                    || swap_params.token_to_address == pool_key.token1,
                'invalid swap params [2]'
            );

            // Perform swap before deposit to adjust balances
            swap_params.swap(IPriceOracleDispatcher { contract_address: self.oracle.read() });

            // Deposit remaining balances
            let token0_bal = ERC20Helper::balanceOf(pool_key.token0, this);
            let token1_bal = ERC20Helper::balanceOf(pool_key.token1, this);
            self._ekubo_deposit(this, token0_bal, token1_bal, this);

            // Assert that most of the balance is used
            let token0_bal_new = ERC20Helper::balanceOf(pool_key.token0, this);
            let token1_bal_new = ERC20Helper::balanceOf(pool_key.token1, this);
            assert(
                safe_decimal_math::is_under_by_percent_bps(token0_bal_new, token0_bal, 1),
                'invalid token0 balance'
            );
            assert(
                safe_decimal_math::is_under_by_percent_bps(token1_bal_new, token1_bal, 1),
                'invalid token1 balance'
            );
        }
    }

    #[abi(embed_v0)]
    impl VesuERC20Impl of IERC20Mixin<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            let unminted_shares = self.reward_share.get_total_unminted_shares();
            let total_supply: u256 = self.erc20.total_supply()
                + unminted_shares.try_into().unwrap();

            total_supply
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let (additional_shares, _, _) = self.reward_share.get_additional_shares(account);
            self.erc20.balance_of(account) + additional_shares.into()
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20.transfer(recipient, amount)
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.erc20.transfer_from(sender, recipient, amount)
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }

        fn name(self: @ContractState) -> ByteArray {
            self.erc20.name()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc20.symbol()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.erc20.decimals()
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self.total_supply()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.transfer_from(sender, recipient, amount)
        }
    }

    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut state = self.get_contract_mut();
            state._handle_reward_shares(from, amount, 0);
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut state = self.get_contract_mut();
            state._handle_reward_shares(recipient, 0, amount);
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn _handle_reward_shares(
            ref self: ContractState,
            from: ContractAddress,
            unminted_shares: u256,
            minted_shares: u256
        ) {
            if (from.is_zero()) {
                return;
            }

            let (additional_shares, last_block, pending_round_points) = self
                .reward_share
                .get_additional_shares(from);

            // settle any additional shares of the from address
            let additional_u256: u256 = additional_shares.try_into().unwrap();
            if (self.is_incentives_on.read()) {
                let user_shares = self.erc20.balance_of(from);

                // update rewards state for from address
                let mut new_shares = user_shares + additional_u256 - unminted_shares;
                let total_supply = self.total_supply() - minted_shares;
                self
                    .reward_share
                    .update_user_rewards(
                        from,
                        new_shares.try_into().unwrap(),
                        additional_shares,
                        last_block,
                        pending_round_points,
                        total_supply.try_into().unwrap()
                    );
            }

            if (additional_u256 > 0) {
                // mint after updating rewards bcz mint will recursively call this hook
                // and updating rewards will before will make additional_shares 0
                // and avoid calling mint again
                self.erc20.mint(from, additional_shares.try_into().unwrap());
            }
        }

        fn set_sqrt_lower_upper(ref self: ContractState, bounds: Bounds) -> (u256, u256) {
            self.bounds_settings.write(bounds);

            // we compute sqrt_lower and sqrt_upper when bounds are set and store them in storage
            // would be efficient.
            let sqrt_lower = ekuboLibDispatcher().tick_to_sqrt_ratio(bounds.lower);
            let sqrt_upper = ekuboLibDispatcher().tick_to_sqrt_ratio(bounds.upper);
            self.sqrt_lower.write(sqrt_lower);
            self.sqrt_upper.write(sqrt_upper);
            (sqrt_lower, sqrt_upper)
        }

        fn _pay_ekubo(
            ref self: ContractState, sender: ContractAddress, token: ContractAddress, amount: u256
        ) {
            let this = get_contract_address();
            let positions_disp = self.ekubo_positions_contract.read();
            if (this == sender) {
                ERC20Helper::transfer(token, positions_disp.contract_address, amount);
            } else {
                ERC20Helper::transfer_from(token, sender, positions_disp.contract_address, amount);
            }
        }

        fn get_pool_price(self: @ContractState) -> PoolPrice {
            let disp = self.ekubo_positions_contract.read();
            return disp.get_pool_price(self.pool_key.read());
        }

        fn _withdraw_position(ref self: ContractState, liquidity: u256) -> (u128, u128) {
            let disp = self.ekubo_positions_contract.read();
            return disp
                .withdraw(
                    self.contract_nft_id.read(),
                    self.pool_key.read(),
                    self.bounds_settings.read(),
                    liquidity.try_into().unwrap(),
                    0x00,
                    0x00,
                    false
                );
        }

        // @returns liquidity
        fn _ekubo_deposit(
            ref self: ContractState,
            sender: ContractAddress,
            amount0: u256,
            amount1: u256,
            receiver: ContractAddress
        ) -> u256 {
            let pool_key = self.pool_key.read();
            let token0 = pool_key.token0;
            let token1 = pool_key.token1;
            let positions_disp = self.ekubo_positions_contract.read();

            // send funds to ekubo
            self._pay_ekubo(sender, token0, amount0);
            self._pay_ekubo(sender, token1, amount1);

            let liq_before_deposit = self.get_position().liquidity;
            let nft_id = self.contract_nft_id.read();
            if nft_id == 0 {
                let nft_id: u64 = IEkuboNFTDispatcher {
                    contract_address: self.ekubo_positions_nft.read()
                }
                    .get_next_token_id();
                self.contract_nft_id.write(nft_id);
                positions_disp
                    .mint_and_deposit(self.pool_key.read(), self.bounds_settings.read(), 0);
            } else {
                positions_disp
                    .deposit(nft_id, self.pool_key.read(), self.bounds_settings.read(), 0);
            }
            // clear any unused tokens and send to receiver
            positions_disp.clear_minimum_to_recipient(token0, 0, receiver);
            positions_disp.clear_minimum_to_recipient(token1, 0, receiver);

            let liq_after_deposit = self.get_position().liquidity;
            return (liq_after_deposit - liq_before_deposit).into();
        }

        fn _collect_strat_fee(ref self: ContractState) -> (u256, u256) {
            // collect fees from ekubo positions
            let nft_id = self.contract_nft_id.read();
            if (nft_id == 0) {
                return (0, 0);
            }

            let pool_key = self.pool_key.read();
            let bounds = self.bounds_settings.read();
            let token0 = pool_key.token0;
            let token1 = pool_key.token1;
            let (fee0, fee1) = self
                .ekubo_positions_contract
                .read()
                .collect_fees(nft_id, pool_key, bounds);

            // compute our fee share
            let fee_settings = self.fee_settings.read();
            let bps = fee_settings.fee_bps;
            let collector = fee_settings.fee_collector;
            let fee_eth = (fee0.into() * bps) / 10000;
            let fee_wst_eth = (fee1.into() * bps) / 10000;

            // transfer to fee collector
            ERC20Helper::transfer(token0, collector, fee_eth);
            ERC20Helper::transfer(token1, collector, fee_wst_eth);

            // return remaining amounts
            (fee0.into() - fee_eth, fee1.into() - fee_wst_eth)
        }

        fn _convert_to_shares(self: @ContractState, liquidity: u256) -> u256 {
            let supply = self.total_supply();
            if (supply == 0) {
                return liquidity;
            }
            let position = self.get_position();
            let total_liquidity = position.liquidity;
            return (liquidity * supply) / total_liquidity.into();
        }

        fn _convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            let supply = self.total_supply();
            if (supply == 0) {
                return shares;
            }

            let position = self.get_position();
            let total_liquidity = position.liquidity;
            return (shares * total_liquidity.into()) / supply;
        }

        fn _max_liquidity(self: @ContractState, amount0: u256, amount1: u256) -> u256 {
            let current_sqrt_price = self.get_pool_price().sqrt_ratio;
            let liquidity = ekuboLibDispatcher()
                .max_liquidity(
                    current_sqrt_price,
                    self.sqrt_lower.read(),
                    self.sqrt_upper.read(),
                    amount0.try_into().unwrap(),
                    amount1.try_into().unwrap()
                );
            return liquidity.into();
        }
    }

    /// hooks defining before and after actions for the harvest function
    impl HarvestHooksImpl of HarvestHooksTrait<ContractState> {
        fn before_update(ref self: ContractState) -> HarvestBeforeHookResult {
            // dont do any swap here
            // returning STRK address will do nothing, just claim STRK and leaves it
            // The handling is anyways done in the harvest function after simple_harvest call
            HarvestBeforeHookResult { baseToken: constants::STRK_ADDRESS() }
        }

        fn after_update(ref self: ContractState, token: ContractAddress, amount: u256) {
            let fee_amount = amount * self.fee_settings.read().fee_bps / 10000;
            if (fee_amount > 0) {
                ERC20Helper::transfer(token, self.fee_settings.read().fee_collector, fee_amount);
            }
            // leave the rest in the contract, will be handled by the harvest function
        }
    }
}
