// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {IERC20}      from "openzeppelin/token/ERC20/IERC20.sol";

contract aCNVRedemption {

    // ---------------------------------------------------------
    // Events
    // ---------------------------------------------------------

    event Redemption(address indexed redeemer, uint256 output);

    // ---------------------------------------------------------
    // Constants
    // ---------------------------------------------------------

    IERC20 public constant CNV = IERC20(0x000000007a58f5f58E697e51Ab0357BC9e260A04);

    IERC20 public constant aCNV = IERC20(0x6Ff0106D34FEEe8A8aCF2e7b9168480f86B82E2f);

    // ---------------------------------------------------------
    // Mutables
    // ---------------------------------------------------------

    mapping(address => bool) hasRedeemed;

    // ---------------------------------------------------------
    // Actions
    // ---------------------------------------------------------

    // @notice This contract is minted aCNV's totalSupply at CNV launch, redemption rate is 1:1
    function redeem(address to) external returns (uint256 output) {

        require(hasRedeemed[msg.sender] == false, "!ALREADY_REDEEMED");

        output = aCNV.balanceOf(msg.sender);

        hasRedeemed[msg.sender] = true;

        CNV.transfer(to, output);

        emit Redemption(msg.sender, output);
    }
}
