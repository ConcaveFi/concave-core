// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >= 0.8.0;

import {ERC20}      from "solmate/tokens/ERC20.sol";
import {Ownable}    from "openzeppelin/access/Ownable.sol";

contract ConcaveToken is Ownable, ERC20("Concave", "CNV", 18) {

    // ---------------------------------------------------------
    // Events
    // ---------------------------------------------------------

    event MinterSet(
        address indexed caller, 
        address indexed who, 
        bool indexed canMint
    );

    // ---------------------------------------------------------
    // Mutables
    // ---------------------------------------------------------

    mapping(address => bool) public isMinter;

    address[] public minters;

    // ---------------------------------------------------------
    // Access-Controlled Actions
    // ---------------------------------------------------------

    function mint(
        address account,
        uint256 amount
    ) external {

        require(isMinter[msg.sender], "!MINTER");

        _mint(account, amount);
    }

    function burn(
        address account,
        uint256 amount
    ) external {

        require(isMinter[msg.sender], "!MINTER");

        _burn(account, amount);
    }

    function setMinter(
        address who,
        bool canMint
    ) external onlyOwner {

        if (canMint == true && isMinter[who] == false ) minters.push(who);

        isMinter[who] = canMint;

        emit MinterSet(msg.sender, who, canMint);
    }

    // ---------------------------------------------------------
    // Viewables
    // ---------------------------------------------------------

    function mintersLength() external view returns(uint256) {
        return minters.length;
    }
}