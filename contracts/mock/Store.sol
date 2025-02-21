// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@uma/core/contracts/data-verification-mechanism/implementation/Store.sol";

contract MockStore is Store {
    constructor () Store(FixedPoint.fromUnscaledUint(0), FixedPoint.fromUnscaledUint(0), address(0)) {}
}