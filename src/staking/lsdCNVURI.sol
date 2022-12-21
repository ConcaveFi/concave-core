// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/IStakingV1.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./dateTime.sol";
import "./svgs/svg555Helper.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract lsdCNVURI is svg555Helper {
    using Strings for uint256;
    using DateTImeLibrary for uint;
    address CNV_ADDRESS;

    struct LSDPosition {
        string stakePeriod;
        string vAPR;
        string dateUnlocks;
        string dateStaked;
        string currentValue;
        string cnvGained;
        string cnvInitial;
    }

    modifier tokenExists(uint _id) {
        require(
            IStakingV1(CNV_ADDRESS).ownerOf(_id) != address(0),
            "ERC721Metadata: URI query for nonexistent token"
        );
        _;
    }

    constructor(address _cnvAddress) {
        CNV_ADDRESS = _cnvAddress;
    }

    function _getPoolLength(
        uint _poolID
    ) internal pure returns (string memory) {
        if (_poolID == 0) {
            return "360 Days";
        } else if (_poolID == 1) {
            return "180 Days";
        } else if (_poolID == 2) {
            return "90 Days";
        } else if (_poolID == 3) {
            return "45 Days";
        } else return "Unlocked";
    }

    function _formatRewardsEarned(
        uint _initial,
        uint _currentRewards
    ) internal pure returns (string memory) {
        string memory reward = ((_currentRewards - _initial) / 1e18).toString();
        return string(abi.encodePacked(reward, " CNV"));
    }

    function _formatDateUnlocks(
        uint32 _maturity
    ) internal view returns (string memory) {
        return
            _maturity >= block.timestamp
                ? (_maturity - block.timestamp).toString()
                : "0";
    }

    function _getPosition(
        uint _id
    ) internal tokenExists(_id) returns (LSDPosition) {
        (uint amountDeposited, , uint totalRewards) = IStakingV1(CNV_ADDRESS)
            .viewPositionRewards(_id);
        (uint32 poolID, , uint32 maturity, , ) = IStakingV1(CNV_ADDRESS)
            .positions(_id);
        string memory stakePeriod = _getPoolLength(poolID);
        string memory cnvGained = _formatRewardsEarned(
            amountDeposited,
            totalRewards
        );
        string memory deposit = string(
            abi.encodePacked((amountDeposited / 1e18).toString(), " CNV")
        );
        string memory cnvGained = string(
            abi.encodePacked(
                ((currentRewards - amountDeposited) / 1e18).toString(),
                " CNV"
            )
        );
        string memory currentValue = string(
            abi.encodePacked((totalRewards / 1e18), " CNV")
        );
        return
            LSDPosition(
                stakePeriod,
                "Unsure",
                _formatDateUnlocks(maturity),
                "Unsure",
                currentValue,
                cnvGained,
                deposit
            );
    }

    function tokenURI(
        uint256 _tokenId
    ) public view tokenExists(_tokenId) returns (string memory) {
        bytes memory output;
        LSDPosition position = _getPosition(_tokenId);
        string[9] newSVG = _setData(
            position.stakePeriod,
            position.vAPR,
            position.dateStaked,
            position.dateUnlocks,
            position.redeemsIn,
            position.currentValue,
            position.cnvGained,
            position.cnvInitial
        );
        for (uint256 i = 0; i < newSVG.length; i++) {
            output = abi.encodePacked(output, newSVG[i]);
        }
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(output)
                )
            );
    }
}
