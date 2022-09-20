// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
abstract contract GemswapERC20 {
    
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    /* -------------------------------------------------------------------------- */
    /*                                 ERC20 LOGIC                                */
    /* -------------------------------------------------------------------------- */

    string public constant name = 'Concave LP';
    string public constant symbol = 'CNV-LP';
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /* -------------------------------------------------------------------------- */
    /*                              EIP-2612 STORAGE                              */
    /* -------------------------------------------------------------------------- */

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    /* -------------------------------------------------------------------------- */
    /*                                 ERC20 LOGIC                                */
    /* -------------------------------------------------------------------------- */

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked { balanceOf[to] += amount; }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked { totalSupply -= amount; }
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked { balanceOf[to] += amount; }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked { balanceOf[to] += amount; }
        emit Transfer(from, to, amount);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                               EIP-2612 LOGIC                               */
    /* -------------------------------------------------------------------------- */

    function permit(
        address owner, 
        address spender, 
        uint256 value, 
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                )
            );

        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        }
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                block.chainid,
                address(this)
            )
        );
    }
}