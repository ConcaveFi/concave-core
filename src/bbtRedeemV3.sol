// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20     } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Owned      } from "solmate/auth/Owned.sol";
import { ICNV       } from "./ICNV.sol";
import { IRedeemBBT } from "./IRedeemBBT.sol";
import { IStaking   } from "./IStaking.sol";

contract RedeemBBTV3 is Owned {
    ////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////

    // @notice Emitted when a BBT redemption happens.
    event Redemption(
        address indexed _from,
        uint256 indexed _amount
    );

    // @notice Emitted when contract is paused/unpaused
    event Paused (
        address indexed caller,
        bool isPaused
    );

    ////////////////////////////////////////////////////////////////////////////
    // MUTABLE STATE
    ////////////////////////////////////////////////////////////////////////////

    /// @notice address of bbtCNV Token
    address public immutable bbtCNV;
    /// @notice address of CNV Token
    address public immutable CNV;
    /// @notice address of RedeemBBT V1
    address public immutable redeemBBTV1;

    /// @notice address of staking contract
    address public immutable staking;

    uint256 public immutable deadline;
    /// @notice mapping of how many CNV tokens a bbtCNV holder has redeemed
    mapping(address => uint256) public redeemed;
    /// @notice redeem paused;
    bool public paused;

    ////////////////////////////////////////////////////////////////////////////
    // IMMUTABLE STATE
    ////////////////////////////////////////////////////////////////////////////

    string internal constant NONE = "NONE LEFT";

    ////////////////////////////////////////////////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////////////////////////////////////////////////
    constructor(
        address _bbtCNV, 
        address _CNV, 
        address _redeemBBTV1,
        address _staking,
        uint256 _deadline
    ) Owned(msg.sender) {
        bbtCNV = _bbtCNV;
        CNV = _CNV;
        redeemBBTV1 = _redeemBBTV1;
        staking = _staking;
        deadline = _deadline;
    }

    ////////////////////////////////////////////////////////////////////////////
    // ADMIN/MGMT
    ////////////////////////////////////////////////////////////////////////////

    function setPause(
        bool _paused
    ) external onlyOwner {
        paused = _paused;
        emit Paused(msg.sender, _paused);
    }

    ////////////////////////////////////////////////////////////////////////////
    // ACTIONS
    ////////////////////////////////////////////////////////////////////////////

    /// @notice             redeem bbtCNV for CNV following vesting schedule
    /// @param  _amount     amount of CNV to redeem, irrelevant if _max = true
    /// @param  _to         address to which to mint CNV
    /// @param  _max        whether to redeem maximum amount possible
    /// @return amountOut   amount of CNV tokens to be minted to _to
    // update for auto stake / liquidate 
    function redeem(
        uint256 _amount, 
        address _to, 
        bool _max,
        bool _stake,
        uint256 _poolId
    ) external returns (uint256 amountOut) {
        require(!paused, "PAUSED");
        require(block.timestamp < deadline, "PAST DEADLINE");

        uint256 bbtCNVBalance = IERC20(bbtCNV).balanceOf(msg.sender);

        // Check v1/v2 redemption amounts, aggregate with address(this)
        uint256 amountRedeemed = redeemed[msg.sender] + IRedeemBBT(redeemBBTV1).redeemed(msg.sender) + IRedeemBBT(redeemBBTV2).redeemed(msg.sender);

        require(bbtCNVBalance > amountRedeemed, NONE);

        uint256 amountRedeemable = bbtCNVBalance - amountRedeemed;
        amountOut = amountRedeemable;
        if (!_max) {
            require(amountRedeemable >= _amount,"EXCEEDS");
            amountOut = _amount;
        }

        redeemed[msg.sender] += amountOut;

       if (_stake) {
            // they decide to stake so no need to transfer
            IStaking(staking).stake(amountOut, _poolId);
        } else {
            // Else its a firesale at a psm ratio
            ICNV(CNV).transfer(_to, amountOut * 1e18 / rate);
            emit Redemption(msg.sender, amountOut);
        }

    }

}