// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

//  ██████╗ ███████╗███╗   ███╗███████╗██╗    ██╗ █████╗ ██████╗ 
// ██╔════╝ ██╔════╝████╗ ████║██╔════╝██║    ██║██╔══██╗██╔══██╗
// ██║  ███╗█████╗  ██╔████╔██║███████╗██║ █╗ ██║███████║██████╔╝
// ██║   ██║██╔══╝  ██║╚██╔╝██║╚════██║██║███╗██║██╔══██║██╔═══╝ 
// ╚██████╔╝███████╗██║ ╚═╝ ██║███████║╚███╔███╔╝██║  ██║██║     
//  ╚═════╝ ╚══════╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝     

import {FixedPointMathLib}          from "solmate/utils/FixedPointMathLib.sol";
import {TransferHelper}             from "uniswap-lib/TransferHelper.sol";
import {GemswapERC20}               from "./libraries/GemswapERC20.sol";

contract GemswapPair is GemswapERC20 {

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event Mint(address indexed sender, uint256 baseAmount, uint256 quoteAmount);
    event Burn(address indexed sender, uint256 baseAmount, uint256 quoteAmount, address indexed to);
    
    event Swap(
        address indexed sender, 
        uint256 baseAmountIn, 
        uint256 quoteAmountIn, 
        uint256 baseAmountOut, 
        uint256 quoteAmountOut, 
        address indexed to
    );
     
    event Sync(uint112 reserve0, uint112 reserve1);

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    // To avoid division by zero, there is a minimum number of liquidity tokens that always 
    // exist (but are owned by account zero). That number is BIPS_DIVISOR, ten thousand.
    uint256 internal constant PRECISION = 112;
    uint256 internal constant BIPS_DIVISOR = 10_000;
    
    /* -------------------------------------------------------------------------- */
    /*                                MUTABLE STATE                               */
    /* -------------------------------------------------------------------------- */

    address public token0;
    address public token1;

    uint256 public swapFee;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    
    uint112 private reserve0;   
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    function getReserves() public view returns (uint112 _baseReserves, uint112 _quoteReserves, uint32 _lastUpdate) {
        (_baseReserves, _quoteReserves, _lastUpdate) = (reserve0, reserve1, blockTimestampLast);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    uint256 private reentrancyStatus;

    modifier nonReentrant() {
        require(reentrancyStatus == 1, "REENTRANCY");
        reentrancyStatus = 2;
        _;
        reentrancyStatus = 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                               INITIALIZATION                               */
    /* -------------------------------------------------------------------------- */

    error INITIALIZED();

    // called once by the factory at time of deployment
    function initialize(
        address _base, 
        address _quote, 
        uint256 _swapFee
    ) external {
        if (swapFee > 0) revert INITIALIZED();
        (token0, token1, swapFee) = (_base, _quote, _swapFee);
        reentrancyStatus = 1; // init reentrance lock
    }

    error BALANCE_OVERFLOW();

    /// @notice update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 baseBalance, 
        uint256 quoteBalance, 
        uint112 _baseReserves, 
        uint112 _quoteReserves
    ) private {
        unchecked {
            // revert if both balances are greater than 2**112
            if (baseBalance > type(uint112).max || quoteBalance > type(uint112).max) revert BALANCE_OVERFLOW();
            // store current time in memory (mod 2**32 to prevent DoS in 20 years)
            uint32 timestampAdjusted = uint32(block.timestamp % 2**32);
            // store elapsed time since last update
            uint256 timeElapsed = timestampAdjusted - blockTimestampLast; 
            
            // if oracle info hasn"t been updated this block, and there's liquidity, update TWAP variables
            if (timeElapsed > 0 && _baseReserves != 0 && _quoteReserves != 0) {
                price0CumulativeLast += ((uint256(_quoteReserves) << PRECISION) / _baseReserves) * timeElapsed;
                price1CumulativeLast += ((uint256(_baseReserves) << PRECISION) / _quoteReserves) * timeElapsed;
            }

            // sync reserves (make them match balances)
            (reserve0, reserve1, blockTimestampLast) = (uint112(baseBalance), uint112(quoteBalance), timestampAdjusted);
            // emit event since mutable storage was updated
            emit Sync(reserve0, reserve1);
        }
    }

    error INSUFFICIENT_LIQUIDITY_MINTED();

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        // store any variables used more than once in memory to avoid SLOAD"s
        (uint112 _baseReserves, uint112 _quoteReserves,) = getReserves();
        uint256 baseBalance = GemswapERC20(token0).balanceOf(address(this));
        uint256 quoteBalance = GemswapERC20(token1).balanceOf(address(this));
        
        uint256 baseAmount = baseBalance - _baseReserves;
        uint256 quoteAmount = quoteBalance - _quoteReserves;


        uint256 _totalSupply = totalSupply;
        // if lp token total supply is equal to BIPS_DIVISOR (1,000 wei), 
        // amountOut (liquidity) is equal to the root of k minus BIPS_DIVISOR  
        if (_totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(baseAmount * quoteAmount) - BIPS_DIVISOR; 
            _mint(address(0), BIPS_DIVISOR);
        } else {
            liquidity = min(uDiv(baseAmount * _totalSupply, _baseReserves), uDiv(quoteAmount * _totalSupply, _quoteReserves));
        }
        // revert if Lp tokens out is equal to zero
        if (liquidity == 0) revert INSUFFICIENT_LIQUIDITY_MINTED();
        // mint liquidity providers LP tokens        
        _mint(to, liquidity);
        // update mutable storage (reserves + cumulative oracle prices)
        _update(baseBalance, quoteBalance, _baseReserves, _quoteReserves);
        // emit event since mutable storage was updated  
        emit Mint(msg.sender, baseAmount, quoteAmount);
    }

    error INSUFFICIENT_LIQUIDITY_BURNED();

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external nonReentrant returns (uint256 baseAmount, uint256 quoteAmount) {
        // store any variables used more than once in memory to avoid SLOAD"s
        (uint112 _baseReserves, uint112 _quoteReserves,) = getReserves();   
        address _base = token0;                                    
        address _quote = token1;                                    
        uint256 baseBalance = GemswapERC20(_base).balanceOf(address(this));          
        uint256 quoteBalance = GemswapERC20(_quote).balanceOf(address(this));          
        uint256 liquidity = balanceOf[address(this)];                 
        uint256 _totalSupply = totalSupply;
        // division was originally unchecked, using balances ensures pro-rata distribution
        baseAmount = uDiv(liquidity * baseBalance, _totalSupply); 
        quoteAmount = uDiv(liquidity * quoteBalance, _totalSupply);
        // revert if amountOuts are both equal to zero
        if (baseAmount == 0 && quoteAmount == 0) revert INSUFFICIENT_LIQUIDITY_BURNED();
        // burn LP tokens from this contract"s balance
        _burn(address(this), liquidity);
        // return liquidity providers underlying tokens        
        TransferHelper.safeTransfer(_base, to, baseAmount);
        TransferHelper.safeTransfer(_quote, to, quoteAmount);
        // update mutable storage (reserves + cumulative oracle prices)        
        _update(
            GemswapERC20(_base).balanceOf(address(this)), 
            GemswapERC20(_quote).balanceOf(address(this)), 
            _baseReserves, 
            _quoteReserves
        );
        // emit event since mutable storage was updated     
        emit Burn(msg.sender, baseAmount, quoteAmount, to);
    }

    error INSUFFICIENT_OUTPUT_AMOUNT();
    error INSUFFICIENT_LIQUIDITY();
    error INSUFFICIENT_INPUT_AMOUNT();
    error INSUFFICIENT_INVARIANT();
    error INAVLID_TO();

    /// @notice Optimistically swap tokens, will revert if K is not satisfied
    /// @param baseAmountOut - amount of token0 tokens user wants to receive
    /// @param quoteAmountOut - amount of token1 tokens user wants to receive
    /// @param to - recipient of 'output' tokens
    /// @param data - arbitrary data used during flashswaps
    function swap(
        uint256 baseAmountOut, 
        uint256 quoteAmountOut, 
        address to, 
        bytes calldata data
    ) external nonReentrant {
        // revert if both amounts out are zero
        if (baseAmountOut == 0 && quoteAmountOut == 0) revert INSUFFICIENT_OUTPUT_AMOUNT();
        // store reserves in memory to avoid SLOAD"s
        (uint112 _baseReserves, uint112 _quoteReserves,) = getReserves();
        // revert if both amounts out
        if (baseAmountOut > _baseReserves || quoteAmountOut >=_quoteReserves) revert INSUFFICIENT_LIQUIDITY();
        // store any other variables used more than once in memory to avoid SLOAD"s & stack too deep errors
        uint256 baseAmountIn;
        uint256 quoteAmountIn;
        uint256 baseBalance;
        uint256 quoteBalance;

        {
        address _base = token0;
        address _quote = token1;
        // make sure not to send tokens to token contracts
        if (to == _base || to == _quote) revert INAVLID_TO();
        // optimistically transfer "to" token0 tokens
        // optimistically transfer "to" token1 tokens
        if (baseAmountOut > 0) TransferHelper.safeTransfer(_base, to, baseAmountOut); 
        if (quoteAmountOut > 0) TransferHelper.safeTransfer(_quote, to, quoteAmountOut);
        // if data length is greater than 0, initiate flashswap
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, baseAmountOut, quoteAmountOut, data);
        // store token0 token balance of contract in memory
        // store token1 token balance of contract in memory
        baseBalance = GemswapERC20(_base).balanceOf(address(this));
        quoteBalance = GemswapERC20(_quote).balanceOf(address(this));
        } 
        
        // Math was originally unchecked here
        unchecked {
            // calculate baseAmountIn by comparing contracts balance to last known reserve
            // calculate quoteAmountIn by comparing contracts balance to last known reserve
            if (baseBalance > _baseReserves - baseAmountOut) baseAmountIn = baseBalance - (_baseReserves - baseAmountOut);
            if (quoteBalance > _quoteReserves - quoteAmountOut) quoteAmountIn = quoteBalance - (_quoteReserves - quoteAmountOut);
        }
        // revert if user hasn't sent any tokens to the contract 
        if (baseAmountIn == 0 && quoteAmountIn == 0) revert INSUFFICIENT_INPUT_AMOUNT();

        {
        // store swap fee in memory to save SLOAD
        uint256 _swapFee = swapFee;
        // calculate x, y adjusted to account for swap fees 
        // revert if adjusted k (invariant) is less than old k
        uint256 baseBalanceAdjusted = baseBalance * BIPS_DIVISOR - baseAmountIn * _swapFee;
        uint256 quoteBalanceAdjusted = quoteBalance * BIPS_DIVISOR - quoteAmountIn * _swapFee;
        if (baseBalanceAdjusted * quoteBalanceAdjusted < uint256(_baseReserves) * _quoteReserves * 1e8) revert INSUFFICIENT_INVARIANT();
        }

        // update mutable storage (reserves + cumulative oracle prices first tx per block)
        _update(baseBalance, quoteBalance, _baseReserves, _quoteReserves);
        // emit event since mutable storage was updated
        emit Swap(msg.sender, baseAmountIn, quoteAmountIn, baseAmountOut, quoteAmountOut, to);
    }

    // force balances to match reserves
    function skim(address to) external nonReentrant {
        // store any variables used more than once in memory to avoid SLOAD"s
        address _base = token0;
        address _quote = token1;
        // transfer unaccounted reserves -> "to"
        TransferHelper.safeTransfer(_base, to, GemswapERC20(_base).balanceOf(address(this)) - reserve0);
        TransferHelper.safeTransfer(_quote, to, GemswapERC20(_quote).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external nonReentrant {
        _update(
            GemswapERC20(token0).balanceOf(address(this)), 
            GemswapERC20(token1).balanceOf(address(this)), 
            reserve0, 
            reserve1
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                              INTERNAL HELPERS                              */
    /* -------------------------------------------------------------------------- */

    // unchecked division
    function uDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {assembly {z := div(x, y)}}

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {z = x < y ? x : y;}
}

// naming left for old contract support
interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}