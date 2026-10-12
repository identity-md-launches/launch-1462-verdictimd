// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictIMD} from "../../src/VerdictIMD.sol";

/// @dev Finite actor set and independent balances/allowances model for stateful tests.
contract TokenHandler is Test {
    VerdictIMD public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new VerdictIMD();
        uint256 share = 250_000_000 * 10 ** 18;
        for (uint256 i; i < actors.length; ++i) {
            address actor = makeAddr(string.concat("invariant actor ", vm.toString(i)));
            actors[i] = actor;
            expectedBalance[actor] = share;
            require(token.transfer(actor, share), "initial distribution failed");
        }
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maxSpend = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        amount = bound(amount, 0, maxSpend);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectedOverdraw(uint8 fromSeed, uint8 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from] + 1;
        vm.prank(from);
        (bool success,) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(success, "overdraw succeeded");
    }
}
