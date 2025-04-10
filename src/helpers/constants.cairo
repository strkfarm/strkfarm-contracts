use starknet::ContractAddress;
use starknet::contract_address::contract_address_const;

pub const BASIS_POINTS_FACTOR: u32 = 10000;
pub const TWO_POWER_128: u128 = 0xffffffffffffffffffffffffffffffff;
pub const TWO_POWER_256: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

pub const MAX_SLIPPAGE_BPS: u32 = 300; // 3%

pub fn VESU_SINGLETON_ADDRESS() -> ContractAddress {
    contract_address_const::<0x2545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef>()
}

pub fn EKUBO_FEE_COLLECTOR() -> ContractAddress {
    contract_address_const::<0x053c69eDcB1a65A8687Ec7Ad8fC23fD7cc815186fE4380bb6A5bf31df52361FF>()
}

pub fn RE7_XSTRK_POOL() -> ContractAddress {
    contract_address_const::<0x52fb52363939c3aa848f8f4ac28f0a51379f8d1b971d8444de25fbd77d8f161>()
}

pub fn VESU_GENESIS_POOL() -> ContractAddress {
    contract_address_const::<0x4dc4f0ca6ea4961e4c8373265bfd5317678f4fe374d76f3fd7135f57763bf28>()
}

pub fn RE7_SSTRK_POOL() -> ContractAddress {
    contract_address_const::<0x2e06b705191dbe90a3fbaad18bb005587548048b725116bff3104ca501673c1>()
}

pub fn RE7_USDC_POOL() -> ContractAddress {
    contract_address_const::<0x7f135b4df21183991e9ff88380c2686dd8634fd4b09bb2b5b14415ac006fe1d>()
}

pub fn XSTRK_ADDRESS() -> ContractAddress {
    contract_address_const::<0x028d709c875c0ceac3dce7065bec5328186dc89fe254527084d1689910954b0a>()
}

pub fn VESU_POOL_ID() -> felt252 {
    0x04dc4f0ca6ea4961e4c8373265bfd5317678f4fe374d76f3fd7135f57763bf28
}

pub fn NIMBORA_REFERRAL_ADDRESS() -> ContractAddress {
    contract_address_const::<0x769afadf62261c4e21d5ed126ed61ef982a5a2ba2cf7c0d19d98228eee3882c>()
}

pub fn NIMBORA_STRATEGY_ADDRESS() -> ContractAddress {
    contract_address_const::<0x03759ed21701538d2e1bc5896611166a06585cdbbeeddd1fbdd25da10b2174d3>()
}

pub fn STRK_ADDRESS() -> ContractAddress {
    contract_address_const::<0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>()
}

pub fn AVNU_EX() -> ContractAddress {
    contract_address_const::<0x04270219d365d6b017231b52e92b3fb5d7c8378b05e9abc97724537a80e93b0f>()
}

pub fn ZSTRK_ADDRESS() -> ContractAddress {
    // zSTRK address 0x06d8fa671ef84f791b7f601fa79fea8f6ceb70b5fa84189e3159d532162efc21
    3097244274214451443812369799678450109525654513946223778904994245611212438561.try_into().unwrap()
}

pub fn ZUSDC_ADDRESS() -> ContractAddress {
    contract_address_const::<0x047ad51726d891f972e74e4ad858a261b43869f7126ce7436ee0b2529a98f486>()
}

pub fn USDC_ADDRESS() -> ContractAddress {
    contract_address_const::<0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8>()
}

pub fn USDT_ADDRESS() -> ContractAddress {
    contract_address_const::<0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8>()
}

pub fn ETH_ADDRESS() -> ContractAddress {
    contract_address_const::<0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7>()
}

pub fn zETH() -> ContractAddress {
    contract_address_const::<0x1b5bd713e72fdc5d63ffd83762f81297f6175a5e0a4771cdadbc1dd5fe72cb1>()
}


pub fn USER2_ADDRESS() -> ContractAddress {
    contract_address_const::<0x05b55db55f5884856860e63f3595b2ec6b2c9555f3f507b4ca728d8e427b7864>()
}

pub fn ZKLEND_REWARDS_CONTRACT() -> ContractAddress {
    // 0x7bbdf36eb04b347e1ecd9b9b37eeac1688fa252db68888a79fdef358667feb2
    // 3498130911219199049896567985399357292206889985411816585223208585503655329458.try_into().unwrap()
    contract_address_const::<0x7bbdf36eb04b347e1ecd9b9b37eeac1688fa252db68888a79fdef358667feb2>()
}

pub fn ZKLEND_MARKET() -> ContractAddress {
    // 0x04c0a5193d58f74fbace4b74dcf65481e734ed1714121bdc571da345540efa05
    2149625499377050772775701191274921578103398273298955620360611655307104287237.try_into().unwrap()
}

pub fn TEST_VESU_USER() -> ContractAddress {
    contract_address_const::<0x019252b1deef483477c4d30cfcc3e5ed9c82fafea44669c182a45a01b4fdb97a>()
}

pub fn TestUserStrk() -> ContractAddress {
    contract_address_const::<0x00ca1702e64c81d9a07b86bd2c540188d92a2c73cf5cc0e508d949015e7e84a7>()
}

pub fn TestUserStrk2() -> ContractAddress {
    contract_address_const::<0x0457fa71ca2b99b3c98ad6665075a3c39d41ed6ac37a44926128d0c4f3d4f3a8>()
}

pub fn TestUserUsdc() -> ContractAddress {
    contract_address_const::<0x00f5eca8cc85aaabb3d3910add19e9199bf16408a78bf189370e05b9a154d587>()
}

pub fn TestUserStrk3() -> ContractAddress {
    contract_address_const::<0x0213c67ed78bc280887234fe5ed5e77272465317978ae86c25a71531d9332a2d>()
}

// 25k USDC as of 638958
pub fn TestUserUSDCLarge() -> ContractAddress {
    contract_address_const::<0x03495DD1e4838aa06666aac236036D86E81A6553e222FC02e70C2Cbc0062e8d0>()
}

pub fn Oracle() -> ContractAddress {
    contract_address_const::<0x023fb3afbff2c0e3399f896dcf7400acf1a161941cfb386e34a123f228c62832>()
}

pub fn ORACLE_OURS() -> ContractAddress {
    contract_address_const::<0x435ab4d9c05c00455f2cb583d8cead3a6e3e5e713de1890b0bb2dba6b8d8349>()
}

pub fn NOSTRA_EX() -> ContractAddress {
    contract_address_const::<0x6720b763aac6608ceba3f9069bebb0f990cd96b26071b3fa2a2109940f90db2>()
}

pub fn NOSTRA_ETH_COLLATERAL() -> ContractAddress {
    contract_address_const::<0x057146f6409deb4c9fa12866915dd952aa07c1eb2752e451d7f3b042086bdeb8>()
}

pub fn NOSTRA_INTEREST_CONTRACT() -> ContractAddress {
    contract_address_const::<0x59a943ca214c10234b9a3b61c558ac20c005127d183b86a99a8f3c60a08b4ff>()
}

pub fn NOSTRA_USDC_COLLATERAL() -> ContractAddress {
    contract_address_const::<0x05dcd26c25d9d8fd9fc860038dcb6e4d835e524eb8a85213a8cda5b7fff845f6>()
}

pub fn NOSTRA_USDC_DEBT() -> ContractAddress {
    contract_address_const::<0x063d69ae657bd2f40337c39bf35a870ac27ddf91e6623c2f52529db4c1619a51>()
}

pub fn NOSTRA_STRK_DEBT() -> ContractAddress {
    contract_address_const::<0x001258eae3eae5002125bebf062d611a772e8aea3a1879b64a19f363ebd00947>()
}

pub fn NOSTRA_ETH_DEBT() -> ContractAddress {
    contract_address_const::<0x00ba3037d968790ac486f70acaa9a1cab10cf5843bb85c986624b4d0e5a82e74>()
}

pub fn NOSTRA_CDP() -> ContractAddress {
    contract_address_const::<0x73f6addc9339de9822cab4dac8c9431779c09077f02ba7bc36904ea342dd9eb>()
}

pub fn NOSTRA_ETHUSDC_DEGEN_POOL() -> ContractAddress {
    contract_address_const::<0x05e03162008d76cf645fe53c6c13a7a5fce745e8991c6ffe94400d60e44c210a>()
}

pub fn PRAGMA_ORACLE() -> ContractAddress {
    contract_address_const::<0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b>()
}

pub fn USDC_PRAGMA_KEY() -> felt252 {
    6148332971638477636
}

pub fn ETH_PRAGMA_KEY() -> felt252 {
    19514442401534788
}

pub fn ZKLEND_ORACLE_USDC_CONTRACT() -> ContractAddress {
    contract_address_const::<0x65354c0aefe9855866ef8f6215452a83dc3cebcf0100e22374c7da55f76f9b2>()
}

pub fn ZKLEND_ORACLE_ETH_CONTRACT() -> ContractAddress {
    contract_address_const::<0x2030decadaf1ea93c389ca712d15bc6c010c6837a74aa73e36145ebdf64728d>()
}

pub fn OUR_ORACLE_STRK_CONTRACT() -> ContractAddress {
    contract_address_const::<0x7ca92dce6e5f7f81f6c393c647b5c0c266e7663088351a4bd34ee9f88569de5>()
}

pub fn OUR_ORACLE_XSTRK_CONTRACT() -> ContractAddress {
    contract_address_const::<0x46ebe858c4b3c69eecfabdfdbaeb8b966d93281529ee4f18afcd8284adb0c17>()
}

pub fn EKUBO_CORE() -> ContractAddress {
    contract_address_const::<0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b>()
}

pub fn EKUBO_ROUTER() -> ContractAddress {
    contract_address_const::<0x0199741822c2dc722f6f605204f35e56dbc23bceed54818168c4c49e4fb8737e>()
}

pub fn DNMM_USDC() -> ContractAddress {
    contract_address_const::<0x04937b58e05a3a2477402d1f74e66686f58a61a5070fcc6f694fb9a0b3bae422>()
}

pub fn DNMM_STRK() -> ContractAddress {
    contract_address_const::<0x020d5fc4c9df4f943ebb36078e703369c04176ed00accf290e8295b659d2cea6>()
}

pub fn EKUBO_USER_ADDRESS() -> ContractAddress {
    contract_address_const::<0x02545b2e5d519fc230e9cd781046d3a64e092114f07e44771e0d719d148725ef>()
}

pub fn WST_ADDRESS() -> ContractAddress {
    contract_address_const::<0x0057912720381Af14B0E5C87aa4718ED5E527eaB60B3801ebF702AB09139E38b>()
}

pub fn EKUBO_POSITIONS() -> ContractAddress {
    contract_address_const::<0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067>()
}

pub fn EKUBO_POSITIONS_NFT() -> ContractAddress {
    contract_address_const::<0x07b696af58c967c1b14c9dde0ace001720635a660a8e90c565ea459345318b30>()
}
