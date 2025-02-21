// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
import "@uma/core/contracts/common/implementation/TestnetERC20.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/Finder.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/IdentifierWhitelist.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/Store.sol";
import "@uma/core/contracts/data-verification-mechanism/test/MockOracleAncillary.sol";
import "@uma/core/contracts/optimistic-oracle-v3/implementation/OptimisticOracleV3.sol";

contract OracleSandbox {
    Finder public finder;
    OptimisticOracleV3 public oo;
    constructor(address defaultCurrency) {
        finder = new Finder();
        console.log("Deployed Finder at %s", address(finder));
        Store store = new Store(FixedPoint.fromUnscaledUint(0), FixedPoint.fromUnscaledUint(0), address(0));
        console.log("Deployed Store at %s", address(store));
        AddressWhitelist addressWhitelist = new AddressWhitelist();
        console.log("Deployed AddressWhitelist at %s", address(addressWhitelist));
        IdentifierWhitelist identifierWhitelist = new IdentifierWhitelist();
        console.log("Deployed IdentifierWhitelist at %s", address(identifierWhitelist));
        MockOracleAncillary mockOracle = new MockOracleAncillary(address(finder), address(0));
        console.log("Deployed MockOracleAncillary at %s", address(mockOracle));

        finder.changeImplementationAddress(OracleInterfaces.Store, address(store));
        finder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(addressWhitelist));
        finder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(identifierWhitelist));
        finder.changeImplementationAddress(OracleInterfaces.Oracle, address(mockOracle));
        addressWhitelist.addToWhitelist(defaultCurrency);
        identifierWhitelist.addSupportedIdentifier(bytes32("ASSERT_TRUTH"));
        store.setFinalFee(defaultCurrency, FixedPoint.Unsigned(100e18 / 2));

        oo = new OptimisticOracleV3(finder, IERC20(defaultCurrency), 7200);
        console.log("Deployed Optimistic Oracle V3 at %s", address(oo));
        finder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(oo));
    }
}