// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

//  ██████╗ ███████╗███╗   ███╗███████╗██╗    ██╗ █████╗ ██████╗ 
// ██╔════╝ ██╔════╝████╗ ████║██╔════╝██║    ██║██╔══██╗██╔══██╗
// ██║  ███╗█████╗  ██╔████╔██║███████╗██║ █╗ ██║███████║██████╔╝
// ██║   ██║██╔══╝  ██║╚██╔╝██║╚════██║██║███╗██║██╔══██║██╔═══╝ 
// ╚██████╔╝███████╗██║ ╚═╝ ██║███████║╚███╔███╔╝██║  ██║██║     
//  ╚═════╝ ╚══════╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝   

import "uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
import "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import "uniswap-v2-periphery/interfaces/IWETH.sol";
import "uniswap-v2-periphery/interfaces/IERC20.sol";
import "uniswap-lib/TransferHelper.sol";
import "openzeppelin/token/ERC20/extensions/draft-IERC20Permit.sol";

import "./libraries/GemswapLibrary.sol";

interface IERC20PermitAllowed {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract GemswapRouter {

    address public immutable factory;
    address public immutable implementation;
    address public immutable WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    constructor(
        address _factory, 
        address _implementation, 
        address _WETH
    ) {
        factory = _factory;
        implementation = _implementation;
        WETH = _WETH;
    }

    receive() external payable {
        // only accept ETH via fallback from the WETH contract
        assert(msg.sender == WETH); 
    }

    /* -------------------------------------------------------------------------- */
    /*                             ADD LIQUIDITY LOGIC                            */
    /* -------------------------------------------------------------------------- */

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = GemswapLibrary.getReserves(factory, implementation, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = GemswapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'Gemswap: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = GemswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'Gemswap: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) { 
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = GemswapLibrary.pairFor(factory, implementation, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token, 
            WETH, 
            amountTokenDesired, 
            msg.value, 
            amountTokenMin, 
            amountETHMin
        );
        address pair = GemswapLibrary.pairFor(factory, implementation, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = GemswapLibrary.pairFor(factory, implementation, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = GemswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token, 
            WETH, 
            liquidity, 
            amountTokenMin, 
            amountETHMin, 
            address(this), 
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        IUniswapV2Pair(GemswapLibrary.pairFor(factory, implementation, tokenA, tokenB)).permit(
            msg.sender, 
            address(this), 
            approveMax ? type(uint256).max : liquidity, 
            deadline, 
            v, 
            r, 
            s
        );
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH) {
        address pair = GemswapLibrary.pairFor(factory, implementation, token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 amountETH) {
        address pair = GemswapLibrary.pairFor(factory, implementation, token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 SWAP LOGIC                                 */
    /* -------------------------------------------------------------------------- */

    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts, 
        address[] memory path, 
        address _to
    ) internal virtual {
        // unchecked orginally 
        unchecked {
            uint256 pathLength = path.length;
            address _implementation = implementation;
            for (uint256 i; i < pathLength - 1; ++i) {
                (address input, address output) = (path[i], path[i + 1]);
                (address token0,) = GemswapLibrary.sortTokens(input, output);
                uint256 amountOut = amounts[i + 1];
                (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
                address to = i < path.length - 2 ? GemswapLibrary.pairFor(factory, _implementation, output, path[i + 2]) : _to;
                IUniswapV2Pair(GemswapLibrary.pairFor(factory, _implementation, input, output)).swap(
                    amount0Out, 
                    amount1Out, 
                    to, 
                    new bytes(0)
                );
            }
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256[] memory amounts) {
        unchecked {
            address _implementation = implementation;
            amounts = GemswapLibrary.getAmountsOut(factory, _implementation, amountIn, path);
            require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
            TransferHelper.safeTransferFrom(
                path[0], 
                msg.sender, 
                GemswapLibrary.pairFor(factory, _implementation, path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
        }
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256[] memory amounts) {
        address _implementation = implementation;
        amounts = GemswapLibrary.getAmountsIn(factory, implementation, amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], 
            msg.sender, 
            GemswapLibrary.pairFor(factory, _implementation, path[0], path[1]), 
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = GemswapLibrary.getAmountsOut(factory, _implementation, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(GemswapLibrary.pairFor(factory, _implementation, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(    
        uint256 amountOut, 
        uint256 amountInMax, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) public ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = GemswapLibrary.getAmountsIn(factory, _implementation, amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, GemswapLibrary.pairFor(
            factory, 
            _implementation, 
            path[0], 
            path[1]), 
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) public ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = GemswapLibrary.getAmountsOut(factory, _implementation, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], 
            msg.sender, 
            GemswapLibrary.pairFor(factory, _implementation, path[0], path[1]), 
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        address _implementation = implementation;
        amounts = GemswapLibrary.getAmountsIn(factory, _implementation, amountOut, path);
        require(amounts[0] <= msg.value, "EXCESSIVE_INPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(GemswapLibrary.pairFor(factory, _implementation, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    /* -------------------------------------------------------------------------- */
    /*                              PERMIT SWAP LOGIC                             */
    /* -------------------------------------------------------------------------- */

    function swapExactTokensForTokensUsingPermit(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountIn, deadline, v, r, s);
        amounts = swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForTokensUsingPermitAllowed(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    function swapTokensForExactTokensUsingPermit(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountInMax, deadline, v, r, s);
        amounts = swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
    }

    function swapTokensForExactTokensUsingPermitAllowed(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
    }

    function swapTokensForExactETHUsingPermit(    
        uint256 amountOut, 
        uint256 amountInMax, 
        address[] calldata path, 
        address to, 
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountInMax, deadline, v, r, s);
        amounts = swapTokensForExactETH(amountOut, amountInMax, path, to, deadline);
    }

    function swapTokensForExactETHUsingPermitAllowed(    
        uint256 amountOut, 
        uint256 amountInMax, 
        address[] calldata path, 
        address to, 
        uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapTokensForExactETH(amountOut, amountInMax, path, to, deadline);
    }

    function swapExactTokensForETHUsingPermit(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20Permit(path[0]).permit(msg.sender, address(this), amountIn, deadline, v, r, s);
        amounts = swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForETHUsingPermitAllowed(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256[] memory amounts) {
        IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);
        amounts = swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
    }

    /* -------------------------------------------------------------------------- */
    /*               SWAP (supporting fee-on-transfer tokens) LOGIC               */
    /* -------------------------------------------------------------------------- */
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path, 
        address _to
    ) internal virtual {
        address _implementation = implementation;
        // uint256 pathLength = path.length; // removed to avoid stack too deep :(

        for (uint256 i; i < path.length - 1; ++i) {
            
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = GemswapLibrary.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(GemswapLibrary.pairFor(factory, _implementation, input, output));

            uint256 amountOutput;
            
            { // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountOutput = GemswapLibrary.getAmountOut(
                    IERC20(input).balanceOf(address(pair)) - reserveInput, 
                    reserveInput, 
                    reserveOutput
                );
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? GemswapLibrary.pairFor(factory, _implementation, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, GemswapLibrary.pairFor(factory, implementation,path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to) - (balanceBefore) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        require(path[0] == WETH, "INVALID_PATH");
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(GemswapLibrary.pairFor(factory, implementation, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(IERC20(path[path.length - 1]).balanceOf(to) - (balanceBefore) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        TransferHelper.safeTransferFrom(
            path[0], 
            msg.sender, 
            GemswapLibrary.pairFor(factory, implementation, path[0], path[1]), 
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    /* -------------------------------------------------------------------------- */
    /*                              LIBRARY FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        return GemswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        return GemswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountIn) {
        return GemswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        return GemswapLibrary.getAmountsOut(factory, implementation, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        return GemswapLibrary.getAmountsIn(factory, implementation, amountOut, path);
    }
}