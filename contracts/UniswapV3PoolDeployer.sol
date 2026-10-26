// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3PoolDeployer.sol';

import './UniswapV3Pool.sol';

contract UniswapV3PoolDeployer is IUniswapV3PoolDeployer {
    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    /// @inheritdoc IUniswapV3PoolDeployer
    Parameters public override parameters;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    function deploy(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) internal returns (address pool) {
        // 身份参数不走构造函数参数，也不做成部署后的 public initialize()。
        //
        // CREATE2 地址 = keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))[12:]。
        // initCode = creationCode ++ abi.encode(constructorArgs)，所以构造函数参数一变，init code hash 就变。
        // 无参构造让所有池的 init code 相同，hash 是常量（periphery 的 PoolAddress.POOL_INIT_CODE_HASH）。
        // 池子身份只放进 salt = keccak256(abi.encode(token0, token1, fee))；factory 已是 CREATE2 的 deployer，
        // tickSpacing 由 factory 按 fee 决定，两者都不必进 salt。
        // SwapRouter 等因此不用持有池子的 creation bytecode（二十多 KB），用一个 bytes32 就能算出池地址。
        //
        // 这些字段在池子 UniswapV3Pool 里是 immutable，只能在构造函数里赋值，热路径读取也比 SLOAD 便宜。
        // 若部署后再调 public initialize() 写入它们(Parameters)：immutable 写不了，只能改 storage；
        // 而且 CREATE2 地址可预测，部署和初始化之间会被抢跑。
        // 池子已有的 initialize(sqrtPriceX96) 只设初始价格，不属于池子身份，所以留在 storage。
        //
        // 0.7.6 没有 transient storage。先把参数写入本合约，`new` 时池子构造函数通过
        // msg.sender.parameters() 读回（msg.sender 只能是正在执行 deploy 的 Factory），
        // 构造结束后立刻 delete，避免槽里留下上一笔池子的参数。
        parameters = Parameters({factory: factory, token0: token0, token1: token1, fee: fee, tickSpacing: tickSpacing});
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}());
        delete parameters;
    }
}
