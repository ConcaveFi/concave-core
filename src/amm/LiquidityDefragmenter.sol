// // SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity >=0.8.0;

// //  ██████╗ ███████╗███╗   ███╗███████╗██╗    ██╗ █████╗ ██████╗ 
// // ██╔════╝ ██╔════╝████╗ ████║██╔════╝██║    ██║██╔══██╗██╔══██╗
// // ██║  ███╗█████╗  ██╔████╔██║███████╗██║ █╗ ██║███████║██████╔╝
// // ██║   ██║██╔══╝  ██║╚██╔╝██║╚════██║██║███╗██║██╔══██║██╔═══╝ 
// // ╚██████╔╝███████╗██║ ╚═╝ ██║███████║╚███╔███╔╝██║  ██║██║     
// //  ╚═════╝ ╚══════╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝   

// import "uniswap-v2-core/interfaces/IUniswapV2Pair.sol";
// import "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
// import "uniswap-v2-periphery/interfaces/IWETH.sol";
// import "uniswap-lib/TransferHelper.sol";
// import "openzeppelin/token/ERC20/extensions/draft-IERC20Permit.sol";

// interface IERC20PermitAllowed {
//     function permit(
//         address holder,
//         address spender,
//         uint256 nonce,
//         uint256 expiry,
//         bool allowed,
//         uint8 v,
//         bytes32 r,
//         bytes32 s
//     ) external;
// }

// interface IBonding {
//     function purchaseBond(
//         address recipient,
//         address token,
//         uint256 input,
//         uint256 minOutput
//     ) external returns (uint256 output);
// }

// contract LiquidityDefragmenter {

//     address public immutable WETH;
//     constructor(address _WETH) { WETH = _WETH; }

//     /* -------------------------------------------------------------------------- */
//     /*                                 SWAP LOGIC                                 */
//     /* -------------------------------------------------------------------------- */

//     // requires the initial amount to have already been sent to the first pair
//     function _swap(
//         uint256[] memory amounts, 
//         address[] memory path,
//         address[] memory factories, 
//         address _to
//     ) internal virtual returns (uint256 amountOut) {
//         // Math will not reasonably overflow & was orginally unchecked
//         unchecked {
//             // Cache path.length before use in for loop to save gas
//             uint256 length = path.length;
//             // Execute swaps
//             for (uint256 i; i < length - 1; ++i) {
//                 // Cache input and output token for this paticular swap
//                 (address input, address output) = (path[i], path[i + 1]);
//                 // Sort tokens, and calculate amount out for token0 and token1 
//                 (address token0,) = sortTokens(input, output);
//                 (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amounts[i + 1]) : (amounts[i + 1], uint256(0));
//                 // Determine whether we need to send funds to next pair (for next trade), or back to trader (_to)
//                 address to = i < length - 2 ? IUniswapV2Factory(factories[i + 1]).getPair(output, path[i + 2]) : _to;
//                 // Swap input for output tokens, and sent funds to address determined above
//                 IUniswapV2Pair(IUniswapV2Factory(factories[i]).getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
//             }
//             // Return final output amount
//             return amounts[amounts.length - 1];
//         }
//     }

//     function swapExactETHForTokens(
//         uint256 amountOutMin, 
//         address[] calldata path,
//         address[] calldata factories,
//         address to, 
//         uint256 deadline
//     ) external payable returns (uint256[] memory amounts) {
//         // Ensure that deadline has not elapsed
//         require(deadline >= block.timestamp, "EXPIRED");
//         // Ensure that first/input token is WETH
//         require(path[0] == WETH, "INVALID_PATH");
//         // Calculate amounts out for trade
//         amounts = getAmountsOut(msg.value, factories, path);
//         // Wrap raw ETH into WETH before swaping
//         IWETH(WETH).deposit{value: amounts[0]}();
//         // Transfer WETH amount to the first pair 
//         assert(IWETH(WETH).transfer(IUniswapV2Factory(factories[0]).getPair(path[0], path[1]), amounts[0]));
//         // Ensure that output amount is greater than or equal to "minAmountOut" 
//         require(_swap(amounts, path, factories, to) >= amountOutMin, "!OUTPUT");
//     }

//     function swapExactTokensForTokens(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address[] calldata factories,
//         address to,
//         uint256 deadline
//     ) public returns (uint256[] memory amounts) {
//         // Ensure that deadline has not elapsed
//         require(deadline >= block.timestamp, "EXPIRED");
//         // Optimistically calculate swap amounts
//         amounts = getAmountsOut(amountIn, factories, path);
//         // Transfer input token amount from caller to the first pair 
//         TransferHelper.safeTransferFrom(
//             path[0],
//             msg.sender,
//             IUniswapV2Factory(factories[0]).getPair(path[0], path[1]),
//             amounts[0]
//         );
//         // Ensure that output amount is greater than or equal to "minAmountOut" 
//         require(_swap(amounts, path, factories, to) >= amountOutMin, "!OUTPUT");
//     }

//     function swapExactTokensForTokensUsingPermit(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address[] calldata factories,
//         address to,
//         uint256 deadline, uint8 v, bytes32 r, bytes32 s
//     ) external returns (uint256[] memory amounts) {
//         // Approve tokens for spender - https://eips.ethereum.org/EIPS/eip-2612
//         IERC20Permit(path[0]).permit(msg.sender, address(this), amountIn, deadline, v, r, s);

//         amounts = swapExactTokensForTokens(amountIn, amountOutMin, path, factories, to, deadline);
//     }

//     function swapExactTokensForTokensUsingPermitAllowed(
//         uint256 amountIn,
//         uint256 amountOutMin,
//         address[] calldata path,
//         address[] calldata factories,
//         address to,
//         uint256 deadline, uint256 nonce, uint8 v, bytes32 r, bytes32 s
//     ) external returns (uint256[] memory amounts) {
//         // Approve tokens for spender - https://eips.ethereum.org/EIPS/eip-2612
//         IERC20PermitAllowed(path[0]).permit(msg.sender, address(this), nonce, deadline, true, v, r, s);

//         amounts = swapExactTokensForTokens(amountIn, amountOutMin, path, factories, to, deadline);
//     }

//     /* -------------------------------------------------------------------------- */
//     /*                                HELPER LOGIC                                */
//     /* -------------------------------------------------------------------------- */

//     // returns sorted token addresses, used to handle return values from pairs sorted in this order
//     function sortTokens(
//         address tokenA, 
//         address tokenB
//     ) internal pure returns (address token0, address token1) {
//         (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
//         require(token0 != address(0), "ZERO_ADDRESS");
//     }

//     // performs chained getAmountOut calculations on any number of pairs + factories
//     function getAmountsOut(
//         uint256 amountIn,
//         address[] calldata factories,
//         address[] calldata path
//     ) public view returns (uint256[] memory amounts) {
        
//         amounts = new uint256[](path.length);
//         amounts[0] = amountIn;
        
//         uint256 reserve0; 
//         uint256 reserve1;
//         uint256 reserveIn;
//         uint256 reserveOut;
//         uint256 length = path.length - 1;

//         for (uint256 i; i < length;) {
            
//             // Unchecked because "i" cannot reasonably overflow
//             unchecked {
//                 (address token0,) = sortTokens(path[i], path[i + 1]);
//                 (reserve0, reserve1,) = IUniswapV2Pair(IUniswapV2Factory(factories[i]).getPair(path[i], path[i + 1])).getReserves();
//                 (reserveIn, reserveOut) = path[i] == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
//             }

//             uint256 amountInWithFee = amountIn * 997;
//             uint256 numerator = amountInWithFee * reserveOut;
//             uint256 denominator = reserveIn * 1000 + amountInWithFee;

//             // Unchecked because "i" cannot reasonably overflow & ivision was originally unchecked
//             unchecked {
//                 amounts[i + 1] = numerator / denominator;
//                 ++i;
//             }
//         }         
//     }
// }