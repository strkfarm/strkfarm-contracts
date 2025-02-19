#[starknet::contract]
pub mod DefiSpringSNFMock {
    use strkfarm_contracts::helpers::constants;
    use strkfarm_contracts::components::harvester::defi_spring_default_style::{
        ISNFClaimTrait
    };
    use strkfarm_contracts::helpers::ERC20Helper;
    use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::get_caller_address;

    #[storage]
    pub struct Storage {
    }

    #[abi(embed_v0)]
    pub impl DefiSpringSNFMockImpl of ISNFClaimTrait<ContractState> {
        fn claim(ref self: ContractState, amount: u128, proof: Span<felt252>) {
            println!("Claiming {} STRK", amount);   
            ERC20Helper::transfer(constants::STRK_ADDRESS(), get_caller_address(), amount.into());
        }
    }
}