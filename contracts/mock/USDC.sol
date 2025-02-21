// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20, ERC20Permit {
    constructor () ERC20("USD Coin", "USDC") ERC20Permit("USDC") {
        _mint(msg.sender, 1000000 ether);
    }
}