// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictIMD} from "../src/VerdictIMD.sol";
import {TokenHandler} from "./helpers/TokenHandler.sol";

contract VerdictIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    TokenHandler private handler;
    VerdictIMD private token;

    function setUp() public {
        handler = new TokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectedOverdraw.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsFixedAndEveryUnitIsAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_BalancesAndAllowancesMatchIndependentModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
