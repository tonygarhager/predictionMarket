// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@uma/core/contracts/data-verification-mechanism/implementation/Finder.sol";

contract MockFinder is Finder {
    constructor () Finder() {}
}