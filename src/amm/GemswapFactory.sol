// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

//  ██████╗ ███████╗███╗   ███╗███████╗██╗    ██╗ █████╗ ██████╗ 
// ██╔════╝ ██╔════╝████╗ ████║██╔════╝██║    ██║██╔══██╗██╔══██╗
// ██║  ███╗█████╗  ██╔████╔██║███████╗██║ █╗ ██║███████║██████╔╝
// ██║   ██║██╔══╝  ██║╚██╔╝██║╚════██║██║███╗██║██╔══██║██╔═══╝ 
// ╚██████╔╝███████╗██║ ╚═╝ ██║███████║╚███╔███╔╝██║  ██║██║     
//  ╚═════╝ ╚══════╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝   

import {Ownable} from "openzeppelin/access/Ownable.sol";

contract GemswapFactory is Ownable {

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */
    
    uint256 typeCount; // amount of pool types
    address[] public allPairs;
    mapping(uint256 => bool) public typeAllowed;
    mapping(uint256 => address) public typeToImplementation;
    mapping(address => mapping(address => mapping(uint256 => address))) private _getPair;

    /* -------------------------------------------------------------------------- */
    /*                               PUBLIC LOGIC                                 */
    /* -------------------------------------------------------------------------- */

    error IDENTICAL_ADDRESSES();
    error PAIR_ALREADY_EXISTS();
    error ZERO_ADDRESS();
    error POOL_NOT_ALLOWED();

    function createPair(
        address tokenA, 
        address tokenB, 
        uint256 poolType
    ) public returns (address pair) {

        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(_getPair[token0][token1][poolType] == address(0), "PAIR_ALREADY_EXISTS");
        require(typeAllowed[poolType] == true, "POOL_NOT_ALLOWED");

        pair = _clonePair(typeToImplementation[poolType], keccak256(abi.encodePacked(token0, token1, poolType)));
        IGemswap(pair).initialize(token0, token1, 25);
        
        _getPair[token0][token1][poolType] = pair;
        _getPair[token1][token0][poolType] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        return createPair(tokenA, tokenB, 1);
    }

    function getPair(address tokenA, address tokenB, uint256 poolType) external view returns (address pair) {
        pair = _getPair[tokenA][tokenB][poolType];
        require(pair != address(0), "!nonexistent");
    }

    function getPair(address tokenA, address tokenB) external view returns (address pair) {
        pair = _getPair[tokenA][tokenB][1];
    }
    
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /* -------------------------------------------------------------------------- */
    /*                              MANAGEMENT LOGIC                              */
    /* -------------------------------------------------------------------------- */

    function newPoolType(address impl) external onlyOwner {
        unchecked { ++typeCount; }
        typeToImplementation[typeCount] = impl;
    }

    function allowPoolType(uint256 poolType, bool allowed) external onlyOwner {
        typeAllowed[poolType] = allowed;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CLONE LOGIC                                */
    /* -------------------------------------------------------------------------- */

    function _clonePair(address impl, bytes32 salt) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, impl))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
            // WAGMI send it
            if iszero(instance) { revert(3, 3) }
        }
    }
}

interface IGemswap {
    function initialize(address token0, address token1, uint256 swapFee) external;
}