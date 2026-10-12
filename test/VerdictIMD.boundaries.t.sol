// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictIMD} from "src/VerdictIMD.sol";

/// @dev Complements the deployment/basic ERC-20 suite with allowance boundaries and lifecycles.
/// forge-config: default.fuzz.runs = 1000
contract VerdictIMDBoundariesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    VerdictIMD private token;
    address private holder;
    address private receiver;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new VerdictIMD();
        holder = makeAddr("boundary holder");
        receiver = makeAddr("boundary receiver");
        spender = makeAddr("boundary spender");
        otherSpender = makeAddr("boundary other spender");
    }

    function test_OneBaseUnitCanMoveAndReturnThroughAnApproval() public {
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, address(this), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, address(this), 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintTransferCannotWrapBalancesEvenWithInfiniteApproval() public {
        bytes memory reason = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(reason);
        token.transfer(receiver, type(uint256).max);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(address(this), receiver, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), receiver, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(receiver), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalDoesNotApplyToADifferentOwner() public {
        assertTrue(token.transfer(holder, 2));
        assertTrue(token.transfer(receiver, 2));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(receiver, spender, 1);
        assertEq(token.balanceOf(receiver), 2);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(receiver, spender), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, spender, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(receiver), 2);
    }

    function test_ApprovalsCannotBeDelegatedTransitively() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.approve(otherSpender, type(uint256).max));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1
            )
        );
        vm.prank(otherSpender);
        token.transferFrom(holder, receiver, 1);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.allowance(spender, otherSpender), type(uint256).max);
    }

    function test_OwnerTransferFromRequiresSelfApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(address(this), receiver, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(receiver), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), receiver, 1));
        assertEq(token.balanceOf(receiver), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_InfiniteApprovalCanBeLoweredAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), receiver, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), receiver, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), receiver, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(receiver), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ZeroDelegatedTransferPreservesFiniteAndInfiniteAllowance() public {
        uint256[2] memory budgets = [uint256(1), type(uint256).max];
        for (uint256 i; i < budgets.length; ++i) {
            vm.prank(holder);
            assertTrue(token.approve(spender, budgets[i]));
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Transfer(holder, receiver, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(holder, receiver, 0));
            assertEq(token.allowance(holder, spender), budgets[i]);
            assertEq(token.balanceOf(holder), 0);
            assertEq(token.balanceOf(receiver), 0);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        uint256[3] memory budgets = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < budgets.length; ++i) {
            assertTrue(token.approve(spender, budgets[i]));
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), budgets[i]);
        }
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderIsRejectedForZeroAndMaximumApproval() public {
        uint256[2] memory budgets = [uint256(0), type(uint256).max];
        for (uint256 i; i < budgets.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
            token.approve(address(0), budgets[i]);
        }
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedSelfOverdrawRestoresAllowanceAndAllowsValidRetry() public {
        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalancePreservesApprovalForRetry(
        uint256 balance,
        uint256 amount,
        bool infinite
    ) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(holder, receiver, amount);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        // No second approval: funding the shortfall must make the original authorization usable.
        assertTrue(token.transfer(holder, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, receiver, amount));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(receiver), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(holder, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceOverdrawRevertsDespiteSufficientBalance(
        uint256 balance,
        uint256 approved,
        uint256 amount
    ) public {
        balance = bound(balance, 1, SUPPLY);
        approved = bound(approved, 0, balance - 1);
        amount = bound(amount, approved + 1, balance);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount
            )
        );
        vm.prank(spender);
        token.transferFrom(holder, receiver, amount);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacingApprovalIsIdempotentAndIsolated(uint256 old, uint256 replacement)
        public
    {
        assertTrue(token.approve(spender, 1));
        vm.startPrank(holder);
        assertTrue(token.approve(otherSpender, type(uint256).max));
        assertTrue(token.approve(spender, old));
        assertEq(token.allowance(holder, spender), old);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(holder, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();

        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(holder, otherSpender), type(uint256).max);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(spender, holder), 0);
        // An empty holder may approve any uint256 without reserving or minting tokens.
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExhaustedApprovalDoesNotReviveWhenBalanceReturns(
        uint256 amount,
        uint256 first
    ) public {
        amount = bound(amount, 1, SUPPLY);
        first = bound(first, 0, amount);
        assertTrue(token.transfer(holder, amount));
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, receiver, first));
        assertEq(token.allowance(holder, spender), amount - first);
        assertEq(token.balanceOf(holder), amount - first);
        assertEq(token.balanceOf(receiver), first);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, receiver, amount - first));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(receiver), amount);

        vm.prank(receiver);
        assertTrue(token.transfer(holder, amount));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, receiver, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferChangesOnlyFiniteAllowance(
        uint256 balance,
        uint256 approved,
        uint256 amount,
        bool infinite,
        bool ownerIsSpender
    ) public {
        balance = bound(balance, 0, SUPPLY);
        approved = infinite ? type(uint256).max : bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, balance < approved ? balance : approved);
        address caller = ownerIsSpender ? holder : spender;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(caller, approved));

        vm.prank(caller);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, caller), infinite ? type(uint256).max : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
