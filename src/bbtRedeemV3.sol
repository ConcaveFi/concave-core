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
        address _staking
    ) Owned(msg.sender) {
        bbtCNV = _bbtCNV;
        CNV = _CNV;
        redeemBBTV1 = _redeemBBTV1;
        staking = _staking;
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

    // contrast uma oracle integration no longer a need for a bonding curve so then whats the gimmick apart from the time 
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
        bool _max
    ) external returns (uint256 amountOut) {
        // Check if it's paused
        require(!paused, "PAUSED");
        // Get user bbtCNV balance, and get amount already redeemed.
        // If already redeemed full balance - revert on "FULLY_REDEEMED" since
        // all balance has already been redeemed.
        uint256 bbtCNVBalance = IERC20(bbtCNV).balanceOf(msg.sender);
        uint256 amountRedeemed = redeemed[msg.sender] + IRedeemBBT(redeemBBTV1).redeemed(msg.sender);
        // still need to check the amount redeemed but the need  to calculate the vesting schedule not relevant
        require(bbtCNVBalance > amountRedeemed, NONE);

        uint256 amountRedeemable = amountVested - amountRedeemed;
        amountOut = amountRedeemable;
        if (!_max) {
            require(amountRedeemable >= _amount,"EXCEEDS");
            amountOut = _amount;
        }

        // Update state to reflect redemption.
        // we don't need to burn the coins, the state is maintained within the contract itself ...
        // 
        redeemed[msg.sender] += amountOut;

        // Stake if they wish to stake

        // Liquidate if they wish to liquidate
        // load the treasury with some dai or something, set approvals there such that
        // if a person requests to liquidate, we can just liquidate the and send it to them
        // Transfer raw cnv if they wish to transfer raw cnv

        // Transfer CNV
        // way we have it set up, we would have to load up the cnv contract
        ICNV(CNV).transfer(_to, amountOut);

        emit Redemption(msg.sender, amountOut);
    }

}