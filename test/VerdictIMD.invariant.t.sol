// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictIMD} from "../src/VerdictIMD.sol";
import {TokenHandler} from "./helpers/TokenHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract VerdictIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    TokenHandler private handler;
    VerdictIMD private token;

    function setUp() public {
        handler = new TokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectedOverdraw.selector;
        selectors[4] = TokenHandler.transferAll.selector;
        selectors[5] = TokenHandler.approveBoundary.selector;
        selectors[6] = TokenHandler.rejectedBalanceOverdraw.selector;
        selectors[7] = TokenHandler.rejectedAllowanceOverdraw.selector;
        selectors[8] = TokenHandler.revokeAndReject.selector;
        selectors[9] = TokenHandler.spendThenRejectReuse.selector;
        selectors[10] = TokenHandler.rejectedZeroReceiver.selector;
        selectors[11] = TokenHandler.rejectedZeroSpender.selector;
        selectors[12] = TokenHandler.roundTrip.selector;
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
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev After any random sequence, every holder can still move its entire balance.
    function afterInvariant() public {
        for (uint8 i = 1; i < 4; ++i) {
            handler.transferAll(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_SupplyIsFixedAndEveryUnitIsAccountedFor();
        invariant_BalancesAndAllowancesMatchIndependentModel();
    }
}
