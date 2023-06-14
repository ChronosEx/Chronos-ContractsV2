// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestPair is ERC20 {

    address private token1;
    address private token2;

    constructor(string memory name, string memory symbol, address _token1, address _token2) ERC20(name, symbol) {
        token1 = _token1;
        token2 = _token2;
    }

    function mint(uint amount) external {
        _mint(msg.sender, amount);
    }

    function claimFees() external returns (uint, uint) {
        return (0,0);
    }

    function tokens() external view returns (address, address) {
        return (token1, token2);
    }

    function isStable() external view returns(bool) {
        return false;
    }
}