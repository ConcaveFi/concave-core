// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

interface IGemswapPair {
    function getReserves() external view returns (
        uint112 baseReserves, 
        uint112 quoteReserves, 
        uint32 lastUpdate
    );
}

library GemswapLibrary {

    uint256 internal constant BIPS_DIVISOR = 10_000;

    function uDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {assembly {z := div(x, y)}}

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA, 
        address tokenB
    ) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, deployer))
            mstore(add(ptr, 0x4c), salt)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }

    error NONEXISTENT_PAIR();

    // calculates the clone address for a pair without making any external calls
    function pairFor(
        address factory,
        address implementation,
        address tokenA, 
        address tokenB 
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = predictDeterministicAddress(implementation, keccak256(abi.encodePacked(token0, token1, uint256(1))), factory);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factory,
        address implementation,
        address tokenA, 
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 baseReserves, uint256 quoteReserves,) = IGemswapPair(pairFor(factory, implementation, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (baseReserves, quoteReserves) : (quoteReserves, baseReserves);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA, 
        uint256 reserveA, 
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        amountB = uDiv(amountA * reserveB, reserveA);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * 9975;
        amountOut = uDiv(amountInWithFee * reserveOut, reserveIn * BIPS_DIVISOR + amountInWithFee);
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut, 
        uint256 reserveIn, 
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        amountIn = uDiv(reserveIn * amountOut * BIPS_DIVISOR, reserveOut - amountOut * 9975) + 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                        SHOULD PROB BE UNCHECKED VVV                        */
    /* -------------------------------------------------------------------------- */

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory,
        address implementation,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        unchecked {
            uint256 pathLength = path.length; // save gas
            
            amounts = new uint256[](pathLength);
            amounts[0] = amountIn;
            
            for (uint256 i; i < pathLength - 1; ++i) {
                (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, implementation, path[i], path[i + 1]);
                amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
            }
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory,
        address implementation,
        uint256 amountOut, 
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        unchecked {
            uint256 pathLength = path.length; // save gas

            amounts = new uint256[](pathLength);
            amounts[pathLength - 1] = amountOut;
            
            for (uint256 i = pathLength - 1; i > 0; --i) {
                (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, implementation, path[i - 1], path[i]);
                amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
            }
        }
    }
}
