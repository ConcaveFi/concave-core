// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract MinimalValueShuttle {

    // ---------------------------------------------------------
    // Events
    // ---------------------------------------------------------

    event ValueShuttled(
        uint256 indexed time,
        uint256 indexed value
    );

    // ---------------------------------------------------------
    // Immutables
    // ---------------------------------------------------------

    address public immutable staking;
    address public immutable token;
    address public immutable treasury;

    constructor(
        address _staking,
        address _token,
        address _treasury
    ) {
        staking     = _staking;
        token       = _token;
        treasury    = _treasury;
    }

    // ---------------------------------------------------------
    // Access-Controlled Actions
    // ---------------------------------------------------------

    function valueAccumulated() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // ---------------------------------------------------------
    // Viewables
    // ---------------------------------------------------------

    function shuttleValue() external returns (uint256 totalValue) {

        require(msg.sender == staking, "!STAKING");
        
        totalValue = valueAccumulated();
        
        require(IERC20(token).transfer(treasury, totalValue), "!TRANSFER");
        
        emit ValueShuttled(block.timestamp,totalValue);
    }
}