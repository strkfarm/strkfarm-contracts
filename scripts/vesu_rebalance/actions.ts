import { VesuRebalanceStrategies, VesuRebalance, getMainnetConfig, Global, Pricer, Web3Number, ContractAddr } from '@strkfarm/sdk';
import { ACCOUNT_NAME, getAccount, getRpcProvider } from '../lib/utils';
import { Contract, TransactionExecutionStatus, uint256 } from 'starknet';

async function main() {
    const contracts = VesuRebalanceStrategies;
    const strategy = contracts[0];
    const config = getMainnetConfig();
    const pricer = new Pricer(config, await Global.getTokens());
    pricer.start();
    await pricer.waitTillReady();
    console.log('Pricer ready');

    const vesuRebalance = new VesuRebalance(config, pricer, strategy);
    // console.log(await vesuRebalance.getTVL())

    const acc = getAccount(ACCOUNT_NAME);
    
    // const depositCalls = await vesuRebalance.depositCall(
    //     new Web3Number("1", 18), ContractAddr.from(acc.address)
    // );
    // const tx = await acc.execute(depositCalls);
    // console.log(tx.transaction_hash);
    // await getRpcProvider().waitForTransaction(tx.transaction_hash, {
    //     successStates: [TransactionExecutionStatus.SUCCEEDED]
    // });
    // console.log('Deposit done');

    // const tvl = await vesuRebalance.getTVL();
    // console.log(`TVL: ${JSON.stringify(tvl)}`);

    // const userTVL = await vesuRebalance.getUserTVL(ContractAddr.from(acc.address));
    // console.log(`User TVL: ${JSON.stringify(userTVL)}`);

    // const positions = await vesuRebalance.getPools();
    // console.log(`Positions: ${JSON.stringify(positions)}`);

    const netApy = await vesuRebalance.netAPY();
    console.log(`Net APY: ${JSON.stringify(netApy)}`);

    const {changes, finalPools} = await vesuRebalance.getRebalancedPositions();
    console.log(`New positions: ${JSON.stringify(changes)}`);

    const _yield = await vesuRebalance.netAPYGivenPools(finalPools);
    console.log(`new APY: ${JSON.stringify(_yield)}`);

    // if (_yield > netApy + 0.01) {
    //     console.log('Rebalancing...');
    //     const call = await vesuRebalance.getRebalanceCall(changes);
    //     const tx = await acc.execute(call);
    //     console.log(tx.transaction_hash);
    //     await getRpcProvider().waitForTransaction(tx.transaction_hash, {
    //         successStates: [TransactionExecutionStatus.SUCCEEDED]
    //     });
    //     console.log('Rebalanced');
    // }
}

if (require.main === module) {
    main();
}
