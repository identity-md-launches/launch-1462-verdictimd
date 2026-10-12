// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictIMD} from "../src/VerdictIMD.sol";

contract VerdictIMDTest is Test {
    // Independent literal catches supply and decimals mistakes in the implementation.
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    VerdictIMD private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new VerdictIMD();
    }

    function test_MetadataAndFullSupplyBelongToDeployer() public view {
        assertEq(token.name(), "VerdictIMD");
        assertEq(token.symbol(), "VERDICT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsSingleMintToImmediateDeployer() public {
        vm.recordLogs();
        vm.prank(alice, bob);
        VerdictIMD deployed = new VerdictIMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));

        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndMoveBack() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ZeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenEmptyAccountTransfers() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferToZeroAddressIncludingZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenSelfTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        token.transfer(address(this), SUPPLY + 1);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);

        assertTrue(token.approve(spender, 40 ether));
        assertEq(token.allowance(address(this), spender), 40 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenApproveZeroSpender() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromDeliversExactAmountAndConsumesAllowance() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));

        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.allowance(address(this), spender), 60 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenSpentAllowanceIsReused() public {
        token.approve(spender, 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_RevocationPreventsFurtherSpending() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenUnapprovedSpenderAttemptsTransferFrom() public {
        token.approve(spender, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenTransferFromExceedsAllowance() public {
        token.approve(spender, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5 ether, 6 ether
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 6 ether);
        assertEq(token.allowance(address(this), spender), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenTransferFromExceedsBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100 ether
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.allowance(alice, spender), 100 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenTransferFromToZeroAddressRestoresAllowance() public {
        token.approve(spender, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100 ether);
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromWithoutAllowanceSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToOwnerConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 100 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 100 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_InfiniteAllowanceStaysInfinite() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100 ether));
        assertTrue(token.transferFrom(address(this), bob, 200 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 300 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 200 ether);
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        token.transfer(alice, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1
            )
        );
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_NoMintBurnAdminOrUpgradeEntrypointsForDeployerOrStranger() public {
        token.transfer(alice, 100 ether);
        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[6] = abi.encodeWithSignature("initialize(address)", bob);
        calls[7] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[12] = abi.encodeWithSignature("freeze(address)", alice);
        calls[13] = abi.encodeWithSignature("seize(address)", alice);
        calls[14] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[15] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            assertFalse(success, "deployer reached an unrequested entry point");
            vm.prank(bob);
            (success,) = address(token).call(calls[i]);
            assertFalse(success, "stranger reached an unrequested entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100 ether);
            assertEq(token.balanceOf(bob), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferUsesOnlyApprovedAmount(uint256 approved, uint256 spent)
        public
    {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.allowance(address(this), spender), approved - spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutMovingTokens(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount
            )
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeFitsSizeLimitAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
