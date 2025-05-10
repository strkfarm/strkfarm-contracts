import { VesuRebalanceStrategies, VesuRebalance, getMainnetConfig, Global, Pricer, Web3Number, ContractAddr } from '@strkfarm/sdk';
import { ACCOUNT_NAME, getAccount, getRpcProvider } from '../lib/utils';
import { Account, Call, Contract, TransactionExecutionStatus, uint256 } from 'starknet';

async function main() {
    const contracts = VesuRebalanceStrategies;
    const strategy = contracts[2];
    const config = getMainnetConfig();
    const pricer = new Pricer(config, await Global.getTokens());
    pricer.start();
    await pricer.waitTillReady();
    console.log('Pricer ready');

    const vesuRebalance = new VesuRebalance(config, pricer, strategy);
    // console.log(await vesuRebalance.getTVL())

    // const acc = getAccount(ACCOUNT_NAME);
    const acc = new Account(getRpcProvider(), process.env.ADDRESS!, process.env.PK!, "1", '0x3');
    
    // const depositCalls = await vesuRebalance.depositCall(
    //     {
    //         tokenInfo: vesuRebalance.asset(),
    //         amount: new Web3Number(0.01, 6)
    //     }, ContractAddr.from(acc.address)
    // );
    // console.log(depositCalls)
    // const gas = await acc.estimateInvokeFee(depositCalls);
    // console.log(`Estimated gas: `, gas);

    const fees = await vesuRebalance.getFee(await vesuRebalance.getPools());
    console.log(`Fees: ${JSON.stringify(fees)}`);
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

    // const netApy = await vesuRebalance.netAPY();
    // console.log(`Net APY: ${JSON.stringify(netApy)}`);

    // const {changes, finalPools} = await vesuRebalance.getRebalancedPositions();
    // console.log(`New positions: ${JSON.stringify(changes)}`);

    // const _yield = await vesuRebalance.netAPYGivenPools(finalPools);
    // console.log(`new APY: ${JSON.stringify(_yield)}`);

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

async function harvest() {
    const contracts = VesuRebalanceStrategies;
    const riskAcc = getAccount('risk-manager', 'accounts-risk.json', process.env.ACCOUNT_SECURE_PASSWORD_RISK);
    const config = getMainnetConfig();
    const pricer = new Pricer(config, await Global.getTokens());
    pricer.start();
    await pricer.waitTillReady();
    console.log('Pricer ready');

    const calls: Call[] = [];
    for (let i = 0; i < contracts.length; i++) {
        const strategy = contracts[i];
        const vesuRebalance = new VesuRebalance(config, pricer, strategy);
        const call = await vesuRebalance.harvest(riskAcc);
        calls.push(...call);
    }
    const _calls = [...calls.slice(0, 4)];
    const gas = await riskAcc.estimateInvokeFee(_calls);
    const tx = await riskAcc.execute(_calls);
    console.log(`Harvest tx: ${tx.transaction_hash}`);
    await getRpcProvider().waitForTransaction(tx.transaction_hash, {
        successStates: [TransactionExecutionStatus.SUCCEEDED]
    });
    console.log('Harvest done');
}

if (require.main === module) {
    // main();
    harvest();
}
