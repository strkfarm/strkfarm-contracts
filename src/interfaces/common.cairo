use starknet::{ClassHash};

#[starknet::interface]
pub trait ICommon<TState> {
    fn upgrade(ref self: TState, new_class: ClassHash);
    fn pause(ref self: TState);
    fn unpause(ref self: TState);
    fn is_paused(self: @TState) -> bool;
}
